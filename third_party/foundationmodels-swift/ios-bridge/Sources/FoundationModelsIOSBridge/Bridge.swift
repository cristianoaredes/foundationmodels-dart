import Foundation
import FoundationModelsCore
import os

/// In-process bridge for iOS (and host debugging on macOS).
///
/// SPC-0064 / TCK-0269: replaces the historical stub that returned
/// `["output": "stub", "done": true]`. All inference paths delegate to
/// `FoundationModelsCore` using the **same param dictionaries** as the macOS
/// JSON-RPC daemon (`JsonRpcHandler`), so the Swift core stays the single
/// source of truth (ADR-0002).
///
/// Flutter adapter tickets U1–U8 extend this surface so the thin plugin can
/// route the full protocol-v2 method table without reimplementing model logic.
///
/// React Native TurboModule / JS host wiring remains a consumer concern
/// (documented residual in `docs/ios.md`).
@objc public final class FoundationModelsBridge: NSObject, @unchecked Sendable {
  @objc public static let shared = FoundationModelsBridge()

  private let runtime = FoundationModelsCore()

  /// In-flight streaming tasks keyed by generation / request id (U1 + U6).
  private let generations = BridgeGenerationRegistry()

  /// Builds daemon-shaped `sessions.respond` params from a simple ObjC-friendly API.
  /// - `input`: user prompt text
  /// - `config`: optional keys — `sessionId`, `modelId`, `instructions`, `temperature`, `maximumResponseTokens`
  public static func respondParams(input: String, config: [String: Any]) -> [String: Any] {
    var params: [String: Any] = [
      "input": input
    ]
    if let sessionId = config["sessionId"] as? String, !sessionId.isEmpty {
      params["sessionId"] = sessionId
    }
    if let modelId = config["modelId"] as? String, !modelId.isEmpty {
      params["modelId"] = modelId
    }
    if let instructions = config["instructions"] as? String {
      params["instructions"] = instructions
    }
    var options: [String: Any] = [:]
    if let temperature = config["temperature"] as? Double {
      options["temperature"] = temperature
    } else if let temperature = config["temperature"] as? NSNumber {
      options["temperature"] = temperature.doubleValue
    }
    if let maxTokens = config["maximumResponseTokens"] as? Int {
      options["maximumResponseTokens"] = maxTokens
    } else if let maxTokens = config["maximumResponseTokens"] as? NSNumber {
      options["maximumResponseTokens"] = maxTokens.intValue
    }
    if !options.isEmpty {
      params["options"] = options
    }
    for (key, value) in config where params[key] == nil {
      params[key] = value
    }
    return params
  }

  // MARK: - Synchronous probes

  @objc public func health() -> [String: Any] {
    var result = runtime.health()
    result["bridge"] = "FoundationModelsIOSBridge"
    result["transport"] = "in-process"
    result["stub"] = false
    return result
  }

  @objc public func availability() -> [String: Any] {
    runtime.availability()
  }

  @objc public func capabilities() -> [String: Any] {
    runtime.capabilities()
  }

  @objc public func createSession(config: [String: Any] = [:]) throws -> [String: Any] {
    try runtime.createSession(params: config)
  }

  @objc public func disposeSession(sessionId: String) throws -> [String: Any] {
    try runtime.disposeSession(params: ["sessionId": sessionId])
  }

  // MARK: - Respond (Swift async — preferred)

  public func respond(input: String, config: [String: Any] = [:]) async throws -> [String: Any] {
    let params = Self.respondParams(input: input, config: config)
    return try await runtime.respond(params: params, toolBridge: nil as Any?)
  }

  /// Low-level escape hatch: pass daemon-shaped params directly.
  public func respond(params: [String: Any]) async throws -> [String: Any] {
    try await runtime.respond(params: params, toolBridge: nil as Any?)
  }

  // MARK: - U1 Streaming

  /// Streams a generation, emitting daemon-v2-shaped event dictionaries.
  ///
  /// Once the first event is emitted, failures are delivered as a terminal
  /// `error` event (function returns normally) — matching the daemon contract.
  public func respondStream(
    params: [String: Any],
    onEvent: @escaping @Sendable ([String: Any]) -> Void
  ) async throws {
    let generationId =
      (params["generationId"] as? String)
      ?? (params["requestId"] as? String)
      ?? "gen_\(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: ""))"

    var streamParams = params
    if streamParams["generationId"] == nil {
      streamParams["generationId"] = generationId
    }
    if streamParams["requestId"] == nil {
      streamParams["requestId"] = generationId
    }
    // Async-safe flag: NSLock is unavailable from async contexts on Swift 6 /
    // macOS 27, so use OSAllocatedUnfairLock for the "first event emitted"
    // terminal rule (0.4 / U1).
    let emittedAny = OSAllocatedUnfairLock(initialState: false)
    // Host callback is non-Sendable from the caller's perspective; box it for
    // Task/stream handoff the same way respondObjC boxes its completion.
    nonisolated(unsafe) let hostOnEvent = onEvent
    let emit: @Sendable ([String: Any]) async throws -> Void = { event in
      var enriched = event
      if enriched["requestId"] == nil {
        enriched["requestId"] = generationId
      }
      emittedAny.withLock { $0 = true }
      hostOnEvent(enriched)
    }

    // U7 duplex: ToolCallbackBridge routes tool_call_* events to the host stream
    // and waits for foundationmodels.tools.result via submitToolResult (with timeout).
    // Static-only tools never call the bridge; attaching it is still correct.
    let toolBridge: Any? = {
      #if canImport(FoundationModels)
      if #available(macOS 26.0, *) {
        let lastToolCallId = OSAllocatedUnfairLock(initialState: Optional<String>.none)
        let registry = self.generations
        return ToolCallbackBridge(
          read: {
            let toolCallId = lastToolCallId.withLock { $0 }
            guard let toolCallId, !toolCallId.isEmpty else {
              throw Self.bridgeNSError(
                code: -32603,
                message: "Tool callback read invoked without a toolCallId.",
                machineCode: "INTERNAL_ERROR",
                data: ["code": "INTERNAL_ERROR", "reason": "missing_tool_call_id"]
              )
            }
            // Host may submit after the request event is observed (Dart autoExecuteTools
            // or manual submitToolResult). Timeout prevents indefinite hang.
            let params = try await registry.waitForToolResult(
              toolCallId: toolCallId,
              timeoutNanoseconds: 120_000_000_000
            )
            return [
              "jsonrpc": "2.0",
              "method": "foundationmodels.tools.result",
              "params": params,
            ]
          },
          emit: { event in
            if let type = event["type"] as? String,
               type == "tool_call_request" || type == "tool_call_delta",
               let tid = event["toolCallId"] as? String {
              lastToolCallId.withLock { $0 = tid }
            }
            try await emit(event)
          }
        )
      }
      #endif
      return nil
    }()

    // Bundle non-Sendable stream operands for Task handoff (Swift 6 sending).
    struct StreamWork: @unchecked Sendable {
      let runtime: FoundationModelsCore
      let params: [String: Any]
      let toolBridge: Any?
      let emit: @Sendable ([String: Any]) async throws -> Void
    }
    let work = StreamWork(
      runtime: runtime,
      params: streamParams,
      toolBridge: toolBridge,
      emit: emit
    )
    let task = Task {
      try await work.runtime.stream(
        params: work.params,
        toolBridge: work.toolBridge,
        emit: work.emit
      )
    }
    generations.register(generationId: generationId, task: task)

    do {
      try await task.value
      generations.failPendingToolWaits(reason: "generation_finished")
      generations.unregister(generationId: generationId)
    } catch {
      generations.failPendingToolWaits(reason: "generation_error")
      generations.unregister(generationId: generationId)
      let cancelled = Task.isCancelled || error is CancellationError
      let hadEvents = emittedAny.withLock { $0 }

      if cancelled {
        // Cancel-before-first-delta and mid-stream cancel: terminal error event.
        onEvent([
          "type": "error",
          "requestId": generationId,
          "code": "GENERATION_CANCELLED",
          "message": "Generation was cancelled before completion.",
          "data": ["code": "GENERATION_CANCELLED"],
        ])
        return
      }

      if hadEvents {
        // Terminal rule: after the first event, do not throw — emit error event.
        let payload = Self.bridgeErrorPayload(from: error)
        onEvent([
          "type": "error",
          "requestId": generationId,
          "code": payload.machineCode,
          "message": payload.message,
          "data": payload.data,
        ])
        return
      }

      throw Self.bridgeNSError(from: error)
    }
  }

  // MARK: - U6 Cancel

  /// Cancels an in-flight generation. Idempotent: unknown / finished ids are no-ops.
  @objc public func cancelGeneration(generationId: String) {
    _ = generations.cancel(generationId: generationId)
  }

  // MARK: - U2 countTokens

  public func countTokens(params: [String: Any]) async throws -> [String: Any] {
    try await runtime.countTokens(params: params)
  }

  // MARK: - U5 transition / prewarm

  public func transitionSession(params: [String: Any]) async throws -> [String: Any] {
    try runtime.transitionSession(params: params)
  }

  public func prewarm(params: [String: Any]) async throws -> [String: Any] {
    try await runtime.prewarmSession(params: params)
  }

  // MARK: - U3 Vision

  public func visionOcr(params: [String: Any]) async throws -> [String: Any] {
    try await runtime.visionOCR(params: params)
  }

  public func visionBarcode(params: [String: Any]) async throws -> [String: Any] {
    try await runtime.visionBarcode(params: params)
  }

  // MARK: - U4 Feedback

  public func logFeedbackAttachment(params: [String: Any]) async throws -> [String: Any] {
    try runtime.logFeedbackAttachment(params: params)
  }

  // MARK: - U7 Tool results (duplex)

  /// Completes a pending tool call from the host. Without an active tool-bridge
  /// duplex channel on the in-process path, returns a structured unsupported
  /// response so hosts can degrade honestly (full duplex arrives with host
  /// wiring that injects a `ToolCallbackBridge`).
  public func submitToolResult(params: [String: Any]) async throws -> [String: Any] {
    if let toolCallId = params["toolCallId"] as? String,
       generations.completeToolResult(toolCallId: toolCallId, params: params) {
      return [
        "ok": true,
        "toolCallId": toolCallId,
        "accepted": true,
      ]
    }
    throw Self.bridgeNSError(
      code: -32020,
      message: "No in-flight tool call is waiting for this result on the in-process bridge.",
      machineCode: "UNSUPPORTED_OPERATION",
      data: [
        "code": "UNSUPPORTED_OPERATION",
        "reason": "submitToolResult requires an active duplex tool bridge registration",
      ]
    )
  }

  // MARK: - ObjC completion API

  /// ObjC/RN-friendly completion. Completion runs on a cooperative task (not
  /// guaranteed main). Hosts that need main-thread UI should hop themselves.
  @objc(respondWithInput:config:completion:)
  public func respondObjC(
    input: String,
    config: [String: Any],
    completion: @escaping (NSDictionary?, NSError?) -> Void
  ) {
    // Capture as untyped Any for cross-isolation handoff under Swift 6.
    nonisolated(unsafe) let finish: (NSDictionary?, NSError?) -> Void = completion
    nonisolated(unsafe) let params = Self.respondParams(input: input, config: config)
    Task {
      do {
        let result = try await self.runtime.respond(params: params, toolBridge: nil as Any?)
        finish(result as NSDictionary, nil)
      } catch {
        finish(nil, error as NSError)
      }
    }
  }

  // MARK: - Error bridging

  private struct BridgeErrorPayload {
    let jsonRpcCode: Int
    let message: String
    let machineCode: String
    let data: [String: Any]
  }

  private static func bridgeErrorPayload(from error: Error) -> BridgeErrorPayload {
    let ns = error as NSError
    if let data = ns.userInfo["data"] as? [String: Any],
       let machine = data["code"] as? String {
      let code = (ns.userInfo["jsonRpcCode"] as? Int) ?? ns.code
      return BridgeErrorPayload(
        jsonRpcCode: code,
        message: ns.localizedDescription,
        machineCode: machine,
        data: data
      )
    }
    // JsonRpcError bridges to NSError with localizedDescription only when
    // fields are not in userInfo — preserve a stable machine code.
    let message = ns.localizedDescription
    if message.localizedCaseInsensitiveContains("cancel") {
      return BridgeErrorPayload(
        jsonRpcCode: -32040,
        message: message,
        machineCode: "GENERATION_CANCELLED",
        data: ["code": "GENERATION_CANCELLED"]
      )
    }
    return BridgeErrorPayload(
      jsonRpcCode: ns.code == 0 ? -32603 : ns.code,
      message: message,
      machineCode: "UNKNOWN_MODEL_ERROR",
      data: ["code": "UNKNOWN_MODEL_ERROR", "detail": message]
    )
  }

  private static func bridgeNSError(from error: Error) -> NSError {
    let payload = bridgeErrorPayload(from: error)
    return bridgeNSError(
      code: payload.jsonRpcCode,
      message: payload.message,
      machineCode: payload.machineCode,
      data: payload.data
    )
  }

  private static func bridgeNSError(
    code: Int,
    message: String,
    machineCode: String,
    data: [String: Any]
  ) -> NSError {
    var payload = data
    if payload["code"] == nil {
      payload["code"] = machineCode
    }
    return NSError(
      domain: "FoundationModelsIOSBridge",
      code: code,
      userInfo: [
        NSLocalizedDescriptionKey: message,
        "jsonRpcCode": code,
        "data": payload,
      ]
    )
  }
}

// MARK: - Generation registry (U6)

/// Boxes a non-Sendable params dict for lock handoff under Swift 6.
private struct ToolParamsBox: @unchecked Sendable {
  let value: [String: Any]
}

/// Tracks in-flight streaming tasks by generation id so `cancelGeneration`
/// can cancel the native Task (mirrors daemon `GenerationTaskRegistry`).
///
/// Also holds duplex tool waiters: `ToolCallbackBridge.read` parks until
/// `submitToolResult` completes the matching `toolCallId` (or timeout/cancel).
final class BridgeGenerationRegistry: @unchecked Sendable {
  private struct State: @unchecked Sendable {
    var tasks: [String: Task<Void, Error>] = [:]
    var toolCompleters: [String: CheckedContinuation<ToolParamsBox, Error>] = [:]
    var earlyResults: [String: ToolParamsBox] = [:]
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  func register(generationId: String, task: Task<Void, Error>) {
    state.withLock { $0.tasks[generationId] = task }
  }

  @discardableResult
  func cancel(generationId: String) -> Bool {
    let (task, completers) = state.withLock { s -> (Task<Void, Error>?, [CheckedContinuation<ToolParamsBox, Error>]) in
      let t = s.tasks.removeValue(forKey: generationId)
      let c = Array(s.toolCompleters.values)
      s.toolCompleters.removeAll()
      s.earlyResults.removeAll()
      return (t, c)
    }
    task?.cancel()
    for cont in completers {
      cont.resume(throwing: CancellationError())
    }
    return task != nil
  }

  func unregister(generationId: String) {
    state.withLock { _ = $0.tasks.removeValue(forKey: generationId) }
  }

  func failPendingToolWaits(reason: String) {
    let completers = state.withLock { s -> [CheckedContinuation<ToolParamsBox, Error>] in
      let c = Array(s.toolCompleters.values)
      s.toolCompleters.removeAll()
      s.earlyResults.removeAll()
      return c
    }
    let err = NSError(
      domain: "FoundationModelsIOSBridge",
      code: -32050,
      userInfo: [
        NSLocalizedDescriptionKey: "Tool wait aborted: \(reason)",
        "code": "TOOL_WAIT_ABORTED",
        "reason": reason,
      ]
    )
    for cont in completers {
      cont.resume(throwing: err)
    }
  }

  func waitForToolResult(
    toolCallId: String,
    timeoutNanoseconds: UInt64
  ) async throws -> [String: Any] {
    if let early = state.withLock({ $0.earlyResults.removeValue(forKey: toolCallId) }) {
      return early.value
    }

    let timeoutTask = Task {
      try await Task.sleep(nanoseconds: timeoutNanoseconds)
      let cont = self.state.withLock { $0.toolCompleters.removeValue(forKey: toolCallId) }
      guard let cont else { return }
      let err = NSError(
        domain: "FoundationModelsIOSBridge",
        code: -32050,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Timed out waiting for tools.result for toolCallId=\(toolCallId).",
          "code": "TOOL_RESULT_TIMEOUT",
          "toolCallId": toolCallId,
        ]
      )
      cont.resume(throwing: err)
    }

    do {
      let box: ToolParamsBox = try await withCheckedThrowingContinuation { cont in
        let early = self.state.withLock { s -> ToolParamsBox? in
          if let e = s.earlyResults.removeValue(forKey: toolCallId) {
            return e
          }
          s.toolCompleters[toolCallId] = cont
          return nil
        }
        if let early {
          cont.resume(returning: early)
        }
      }
      timeoutTask.cancel()
      return box.value
    } catch {
      timeoutTask.cancel()
      throw error
    }
  }

  @discardableResult
  func completeToolResult(toolCallId: String, params: [String: Any]) -> Bool {
    let box = ToolParamsBox(value: params)
    // Returns: (continuation?, acceptedEarlyBuffer)
    // Early buffer only while a generation task is still registered — otherwise
    // stale/orphan submitToolResult is fail-closed (UNSUPPORTED_OPERATION).
    let (cont, acceptedEarly) = state.withLock { s -> (CheckedContinuation<ToolParamsBox, Error>?, Bool) in
      if let c = s.toolCompleters.removeValue(forKey: toolCallId) {
        return (c, false)
      }
      if !s.tasks.isEmpty {
        s.earlyResults[toolCallId] = box
        return (nil, true)
      }
      return (nil, false)
    }
    if let cont {
      cont.resume(returning: box)
      return true
    }
    return acceptedEarly
  }
}
