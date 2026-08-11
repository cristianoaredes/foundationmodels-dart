#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif
import Foundation
import FoundationModelsCore
import FoundationModelsIOSBridge

/// Flutter plugin that bridges platform channels to `FoundationModelsBridge.shared`.
///
/// Design (ADR-0001):
/// - A single MethodChannel (`foundationmodels/rpc`) with a single operation,
///   `invoke`, whose argument is a daemon-shaped envelope:
///   `{"id": "rpc_...", "method": "foundationmodels.<domain>.<op>", "params": {...}}`.
/// - A single EventChannel (`foundationmodels/streams`) whose events are
///   multiplexed by `requestId`; every event map carries `requestId` and, when
///   available, `sessionId`/`traceId`.
/// - Unary success replies with the bare JSON-RPC `result`; failures reply with
///   `FlutterError(code: "<jsonRpcCode>", message: ..., details: errorData)`,
///   where `errorData` carries the stable machine-readable `code`
///   (e.g. CONTEXT_OVERFLOW) — that string, not the numeric code, is the
///   contract Dart maps to typed exceptions.
///
/// This file is intentionally thin: it only translates channel <-> dictionary.
/// All model logic lives upstream in `FoundationModelsCore` and must never be
/// reimplemented here (ADR-0001 §9, non-negotiable).
///
/// Methods marked `UPSTREAM(U1)..(U7)` are written against the *target* Swift
/// API that the ios-bridge will expose (see ADR-0001 §9); they will not
/// compile against the current bridge surface until those tickets land.
public final class FoundationModelsPlugin: NSObject, FlutterPlugin {
    /// Canonical method names routed over the single `invoke` operation.
    enum RPCMethod {
        static let health = "foundationmodels.health"
        static let availability = "foundationmodels.availability"
        static let capabilities = "foundationmodels.capabilities"
        static let countTokens = "foundationmodels.context.countTokens"
        static let sessionCreate = "foundationmodels.sessions.create"
        static let sessionRespond = "foundationmodels.sessions.respond"
        static let sessionStream = "foundationmodels.sessions.stream"
        static let sessionDispose = "foundationmodels.sessions.dispose"
        static let sessionTransition = "foundationmodels.sessions.transition"
        static let sessionPrewarm = "foundationmodels.sessions.prewarm"
        static let generationCancel = "foundationmodels.generation.cancel"
        static let toolsResult = "foundationmodels.tools.result"
        static let visionOcr = "foundationmodels.vision.ocr"
        static let visionBarcode = "foundationmodels.vision.barcode"
        static let feedbackLogAttachment = "foundationmodels.feedback.logAttachment"
    }

    private static let methodChannelName = "foundationmodels/rpc"
    private static let eventChannelName = "foundationmodels/streams"

    private let streamHandler = StreamEventHandler()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = FoundationModelsPlugin()

        // Keep byte-aligned with ios/.../FoundationModelsPlugin.swift.
        // messenger is a method on FlutterPluginRegistrar (call with ()).
        let methodChannel = FlutterMethodChannel(
            name: methodChannelName,
            binaryMessenger: registrar.messenger
        )
        registrar.addMethodCallDelegate(instance, channel: methodChannel)

        let eventChannel = FlutterEventChannel(
            name: eventChannelName,
            binaryMessenger: registrar.messenger
        )
        eventChannel.setStreamHandler(instance.streamHandler)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "invoke" else {
            // Avoid FlutterMethodNotImplemented (mutable global; Swift 6 unsafe).
            result(FlutterError(
                code: "not_implemented",
                message: "Only the \"invoke\" method is supported.",
                details: ["code": "METHOD_NOT_FOUND"]
            ))
            return
        }
        guard
            let envelope = call.arguments as? [String: Any],
            let method = envelope["method"] as? String
        else {
            result(Self.rpcError(
                code: "-32600",
                message: "Invalid envelope: expected {\"id\": ..., \"method\": ..., \"params\": {...}}",
                machineCode: "INVALID_REQUEST"
            ))
            return
        }
        let params = envelope["params"] as? [String: Any] ?? [:]
        let requestId = envelope["id"] as? String
        route(method: method, params: params, requestId: requestId, result: result)
    }

    // MARK: - Envelope router

    private func route(
        method: String,
        params: [String: Any],
        requestId: String?,
        result: @escaping FlutterResult
    ) {
        let bridge = FoundationModelsBridge.shared
        // FlutterResult is not Sendable; box for Task handoff under Swift 6.
        nonisolated(unsafe) let finish: FlutterResult = result

        switch method {
        case RPCMethod.health:
            result(bridge.health())

        case RPCMethod.availability:
            result(bridge.availability())

        case RPCMethod.capabilities:
            result(bridge.capabilities())

        case RPCMethod.countTokens:
            // U2: countTokens on the bridge → core.
            Task {
                do {
                    finish(try await bridge.countTokens(params: params))
                } catch {
                    finish(Self.flutterError(from: error))
                }
            }

        case RPCMethod.sessionCreate:
            // U5: full session config including history is accepted by the
            // core createSession path once the bridge forwards params.
            do {
                result(try bridge.createSession(config: params))
            } catch {
                result(Self.flutterError(from: error))
            }

        case RPCMethod.sessionRespond:
            Task {
                do {
                    finish(try await bridge.respond(params: params))
                } catch {
                    finish(Self.flutterError(from: error))
                }
            }

        case RPCMethod.sessionStream:
            startStreaming(params: params, requestId: requestId, result: result)

        case RPCMethod.sessionDispose:
            guard let sessionId = params["sessionId"] as? String else {
                result(Self.rpcError(
                    code: "-32602",
                    message: "Missing required param: sessionId",
                    machineCode: "INVALID_PARAMS"
                ))
                return
            }
            do {
                result(try bridge.disposeSession(sessionId: sessionId))
            } catch {
                result(Self.flutterError(from: error))
            }

        case RPCMethod.sessionTransition:
            // U5: transitionSession preserves transcript while changing instructions.
            Task {
                do {
                    finish(try await bridge.transitionSession(params: params))
                } catch {
                    finish(Self.flutterError(from: error))
                }
            }

        case RPCMethod.sessionPrewarm:
            // U5: prewarmSession best-effort warm of the model.
            Task {
                do {
                    finish(try await bridge.prewarm(params: params))
                } catch {
                    finish(Self.flutterError(from: error))
                }
            }

        case RPCMethod.generationCancel:
            guard let generationId = params["generationId"] as? String else {
                result(Self.rpcError(
                    code: "-32602",
                    message: "Missing required param: generationId",
                    machineCode: "INVALID_PARAMS"
                ))
                return
            }
            // U6: cancelGeneration — cooperative cancel of the native streaming Task.
            bridge.cancelGeneration(generationId: generationId)
            streamHandler.unregister(generationId: generationId)
            result(["ok": true, "generationId": generationId, "cancelled": true])

        case RPCMethod.toolsResult:
            // U7: submitToolResult — duplex tool calling completer.
            Task {
                do {
                    finish(try await bridge.submitToolResult(params: params))
                } catch {
                    finish(Self.flutterError(from: error))
                }
            }

        case RPCMethod.visionOcr:
            // U3: vision OCR via core VisionHandler.
            Task {
                do {
                    finish(try await bridge.visionOcr(params: params))
                } catch {
                    finish(Self.flutterError(from: error))
                }
            }

        case RPCMethod.visionBarcode:
            // U3: vision barcode via core VisionHandler.
            Task {
                do {
                    finish(try await bridge.visionBarcode(params: params))
                } catch {
                    finish(Self.flutterError(from: error))
                }
            }

        case RPCMethod.feedbackLogAttachment:
            // U4: feedback attachment logging.
            Task {
                do {
                    finish(try await bridge.logFeedbackAttachment(params: params))
                } catch {
                    finish(Self.flutterError(from: error))
                }
            }

        default:
            result(Self.rpcError(
                code: "-32601",
                message: "Method not found: \(method)",
                machineCode: "METHOD_NOT_FOUND"
            ))
        }
    }

    // MARK: - Streaming

    /// Starts a native streaming generation and returns an ack immediately;
    /// deltas arrive on the shared EventChannel multiplexed by `requestId`.
    private func startStreaming(
        params: [String: Any],
        requestId: String?,
        result: @escaping FlutterResult
    ) {
        // The stream's correlation id: prefer an explicit generationId param,
        // fall back to the envelope id. Dart demultiplexes by this value.
        guard let generationId = (params["generationId"] as? String) ?? requestId else {
            result(Self.rpcError(
                code: "-32602",
                message: "Streaming requires params.generationId or an envelope id",
                machineCode: "INVALID_PARAMS"
            ))
            return
        }

        streamHandler.register(generationId: generationId)

        // U1: respondStream — per-delta callback over core stream events.
        let handler = streamHandler
        nonisolated(unsafe) let streamParams = params
        // Debug breadcrumb for host E2E (scratch closeout); keep cheap.
        NSLog("[foundationmodels_apple] startStreaming generationId=%@ paramsKeys=%@",
              generationId, Array(params.keys).sorted().description)
        Task {
            do {
                try await FoundationModelsBridge.shared.respondStream(params: streamParams) { event in
                    var enriched = Self.normalizeStreamEvent(event)
                    if enriched["requestId"] == nil {
                        enriched["requestId"] = generationId
                    }
                    let t = enriched["type"] as? String ?? "?"
                    NSLog("[foundationmodels_apple] stream event type=%@ gen=%@", t, generationId)
                    handler.emit(enriched)
                }
                NSLog("[foundationmodels_apple] respondStream finished gen=%@", generationId)
            } catch {
                // Flat canonical shape — `StreamError.fromMap` on the Dart
                // side reads top-level `code` (stable machine code),
                // `message` and `data` (daemon error.data dictionary).
                let payload = Self.errorPayload(from: error)
                let data = payload["data"] as? [String: Any] ?? ["code": "UNKNOWN_MODEL_ERROR"]
                NSLog("[foundationmodels_apple] respondStream error gen=%@ err=%@",
                      generationId, String(describing: error))
                handler.emit([
                    "type": "error",
                    "requestId": generationId,
                    "code": data["code"] as? String ?? "UNKNOWN_MODEL_ERROR",
                    "message": payload["message"] as? String ?? error.localizedDescription,
                    "data": data,
                ])
            }
        }

        result(["ok": true, "generationId": generationId, "streaming": true])
    }

    /// Maps Core/bridge event dictionaries onto protocol-v2 stream types
    /// expected by `FmStreamEvent.fromMap` (delta→text_delta, text→delta, …).
    private static func normalizeStreamEvent(_ event: [String: Any]) -> [String: Any] {
        var e = event
        let type = e["type"] as? String
        switch type {
        case "delta":
            e["type"] = "text_delta"
            if e["delta"] == nil, let text = e["text"] {
                e["delta"] = text
            }
        case "text_delta":
            if e["delta"] == nil, let text = e["text"] {
                e["delta"] = text
            }
        case "tool_call_result":
            if e["result"] == nil, let output = e["output"] {
                e["result"] = output
            }
        default:
            break
        }
        return e
    }

    // MARK: - Error mapping

    /// Builds a `FlutterError` from any bridge failure.
    ///
    /// Contract: `code` is the JSON-RPC numeric code as a string; `details`
    /// is the daemon's `error.data` dictionary carrying the stable
    /// machine-readable `code` (e.g. CONTEXT_OVERFLOW) that Dart maps to
    /// typed exceptions (ADR-0001 §7.1/§7.3).
    static func flutterError(from error: Error) -> FlutterError {
        let payload = errorPayload(from: error)
        let rpcCode = payload["jsonRpcCode"] as? String ?? "-32603"
        let message = payload["message"] as? String ?? error.localizedDescription
        let data = payload["data"] as? [String: Any] ?? payload
        return FlutterError(code: rpcCode, message: message, details: data)
    }

    /// Extracts the daemon-shaped error payload from a thrown error.
    ///
    /// The bridge is expected to surface failures as NSError whose userInfo
    /// carries `jsonRpcCode` (Int) and `data` ([String: Any], including the
    /// stable machine `code`). Anything else degrades to a generic
    /// UNKNOWN_MODEL_ERROR-shaped payload — typed, never silent (ADR-0001 §7.3).
    static func errorPayload(from error: Error) -> [String: Any] {
        let nsError = error as NSError
        let data = nsError.userInfo["data"] as? [String: Any]
        let machineCode = data?["code"] as? String ?? "UNKNOWN_MODEL_ERROR"
        return [
            "jsonRpcCode": (nsError.userInfo["jsonRpcCode"] as? Int).map(String.init)
                ?? String(nsError.code),
            "message": nsError.localizedDescription,
            "data": data ?? ["code": machineCode],
        ]
    }

    private static func rpcError(code: String, message: String, machineCode: String) -> FlutterError {
        FlutterError(code: code, message: message, details: ["code": machineCode])
    }
}

/// Shared EventChannel handler.
///
/// Threading (ADR-0001 §6): the sink is invoked from a dedicated serial
/// queue; the Flutter engine performs the hop to the platform thread, so the
/// plugin never dispatches to main. State is guarded by a lock because
/// `FlutterEventSink` closures are not `Sendable` under Swift 6.
final class StreamEventHandler: NSObject, FlutterStreamHandler, @unchecked Sendable {
    private let lock = NSLock()
    private let eventQueue = DispatchQueue(
        label: "dev.aredes.foundationmodels.streams",
        qos: .userInitiated
    )
    private var sink: FlutterEventSink?
    private var activeGenerations: Set<String> = []

    func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        lock.lock()
        sink = events
        lock.unlock()
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        lock.lock()
        sink = nil
        let generations = activeGenerations
        activeGenerations.removeAll()
        lock.unlock()

        // Implicit cancel — analogous to the daemon's client-EOF semantics
        // (ADR-0001 §10): abandoning the stream cancels its native generation.
        // UPSTREAM(U6): see ADR-0001 §9. Idempotent.
        for generationId in generations {
            FoundationModelsBridge.shared.cancelGeneration(generationId: generationId)
        }
        return nil
    }

    func register(generationId: String) {
        lock.lock()
        activeGenerations.insert(generationId)
        lock.unlock()
    }

    func unregister(generationId: String) {
        lock.lock()
        activeGenerations.remove(generationId)
        lock.unlock()
    }

    /// Emits a stream event to Dart. `done`/`error` close out the generation
    /// registration (the Dart side closes its StreamController on these).
    ///
    /// Flutter platform channels must be invoked on the platform thread
    /// (main on macOS/iOS). Bridge callbacks may arrive on cooperative pool
    /// threads; hop to main before calling the sink.
    func emit(_ event: [String: Any]) {
        if let type = event["type"] as? String, type == "done" || type == "error",
           let generationId = event["requestId"] as? String {
            unregister(generationId: generationId)
        }
        // Flutter platform channels must be invoked on the platform/main thread.
        // With merged UI+platform threads, prefer direct emit when already on main
        // to avoid re-entrancy deadlocks; hop only when off-main.
        let deliver: () -> Void = { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let sink = self.sink
            self.lock.unlock()
            sink?(event)
        }
        if Thread.isMainThread {
            deliver()
        } else {
            DispatchQueue.main.async(execute: deliver)
        }
    }
}
