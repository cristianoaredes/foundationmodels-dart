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
            result(FlutterMethodNotImplemented)
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

        switch method {
        case RPCMethod.health:
            result(bridge.health())

        case RPCMethod.availability:
            result(bridge.availability())

        case RPCMethod.capabilities:
            result(bridge.capabilities())

        case RPCMethod.countTokens:
            // UPSTREAM(U2): requires ios-bridge extension in the monorepo —
            // `countTokens(params:)` over `SystemLanguageModel.tokenCount(for:)`.
            // See ADR-0001 §9.
            Task {
                do {
                    result(try await bridge.countTokens(params: params))
                } catch {
                    result(Self.flutterError(from: error))
                }
            }

        case RPCMethod.sessionCreate:
            // UPSTREAM(U5): the target signature accepts the full session
            // config, including `history` — the current bridge only takes
            // instructions/options. See ADR-0001 §9.
            result(bridge.createSession(config: params))

        case RPCMethod.sessionRespond:
            Task {
                do {
                    result(try await bridge.respond(params: params))
                } catch {
                    result(Self.flutterError(from: error))
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
            result(bridge.disposeSession(sessionId: sessionId))

        case RPCMethod.sessionTransition:
            // UPSTREAM(U5): requires `transitionSession(params:)` on the bridge
            // (instructions change preserving transcript). See ADR-0001 §9.
            Task {
                do {
                    result(try await bridge.transitionSession(params: params))
                } catch {
                    result(Self.flutterError(from: error))
                }
            }

        case RPCMethod.sessionPrewarm:
            // UPSTREAM(U5): requires `prewarm(params:)` on the bridge.
            // See ADR-0001 §9.
            Task {
                do {
                    result(try await bridge.prewarm(params: params))
                } catch {
                    result(Self.flutterError(from: error))
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
            // UPSTREAM(U6): requires `cancelGeneration(generationId:)` —
            // cooperative cancellation of the native streaming Task. Idempotent
            // by contract: repeated cancels are no-ops. See ADR-0001 §9/§10.
            bridge.cancelGeneration(generationId: generationId)
            streamHandler.unregister(generationId: generationId)
            result(["ok": true, "generationId": generationId, "cancelled": true])

        case RPCMethod.toolsResult:
            // UPSTREAM(U7): requires `submitToolResult(params:)` — duplex tool
            // calling; the bridge completes the pending `toolCallId` completer
            // that blocks native generation. See ADR-0001 §9/§11.
            Task {
                do {
                    result(try await bridge.submitToolResult(params: params))
                } catch {
                    result(Self.flutterError(from: error))
                }
            }

        case RPCMethod.visionOcr:
            // UPSTREAM(U3): requires `visionOcr(params:)` on the bridge,
            // backed by the core's VisionHandler (base64, EXIF-aware).
            // See ADR-0001 §9.
            Task {
                do {
                    result(try await bridge.visionOcr(params: params))
                } catch {
                    result(Self.flutterError(from: error))
                }
            }

        case RPCMethod.visionBarcode:
            // UPSTREAM(U3): requires `visionBarcode(params:)` on the bridge.
            // See ADR-0001 §9.
            Task {
                do {
                    result(try await bridge.visionBarcode(params: params))
                } catch {
                    result(Self.flutterError(from: error))
                }
            }

        case RPCMethod.feedbackLogAttachment:
            // UPSTREAM(U4): requires `logFeedbackAttachment(params:)` on the
            // bridge. See ADR-0001 §9.
            Task {
                do {
                    result(try await bridge.logFeedbackAttachment(params: params))
                } catch {
                    result(Self.flutterError(from: error))
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

        // UPSTREAM(U1): requires `respondStream(params:onEvent:)` — per-delta
        // callback over the core's StreamingDelta + daemon-shaped stream
        // events (run_started, message_start, text_delta, structured_delta,
        // tool_call_start, tool_call_delta, tool_call_result, message_end,
        // done, error). See ADR-0001 §9.
        let handler = streamHandler
        Task {
            do {
                try await FoundationModelsBridge.shared.respondStream(params: params) { event in
                    var enriched = event
                    if enriched["requestId"] == nil {
                        enriched["requestId"] = generationId
                    }
                    handler.emit(enriched)
                }
            } catch {
                handler.emit([
                    "type": "error",
                    "requestId": generationId,
                    "error": Self.errorPayload(from: error),
                ])
            }
        }

        result(["ok": true, "generationId": generationId, "streaming": true])
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
    func emit(_ event: [String: Any]) {
        if let type = event["type"] as? String, type == "done" || type == "error",
           let generationId = event["requestId"] as? String {
            unregister(generationId: generationId)
        }
        eventQueue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let sink = self.sink
            self.lock.unlock()
            sink?(event)
        }
    }
}
