import CoreGraphics
import Foundation
import ImageIO
import Security

#if canImport(FoundationModels)
import FoundationModels
#endif

// TCK-0227 / FND-0147: importing Vision alongside FoundationModels is what
// activates the `_Vision_FoundationModels` cross-import overlay, which is where
// `OCRTool` and `BarcodeReaderTool` live. There is no module of that name to
// import — the compiler pulls it in on seeing both imports in one file.
#if canImport(Vision)
import Vision
#endif

/// Returns true when the current process holds the
/// `com.apple.developer.private-cloud-compute` entitlement.
///
/// Uses `SecTaskCopyValueForEntitlement` on the current task (process token).
/// On an unentitled dev build the entitlement value is nil and this function
/// returns false, allowing the PCC path to emit a typed JSON-RPC error
/// (`reasonCode` "pcc_unavailable", `pccFailureKind` "missing_entitlement")
/// before the SDK's own fatal precondition fires at inference time.
///
/// If the Security framework is unavailable (compile-time), or if SecTask
/// returns an error, the function returns false (fail-safe: better to surface a
/// typed error than to proceed and crash).
private func processPCCEntitlementPresent() -> Bool {
    guard let task = SecTaskCreateFromSelf(nil) else {
        return false
    }
    var error: Unmanaged<CFError>?
    let value = SecTaskCopyValueForEntitlement(
        task,
        "com.apple.developer.private-cloud-compute" as CFString,
        &error
    )
    // A non-nil value (typically CFBoolean true) means the entitlement is
    // present and provisioned; nil means absent (unentitled binary).
    return value != nil
}

public final class FoundationModelsCore {
    /// Thread-safe registry for in-flight sessions, keyed by session id (TCK-0129). Replaces a
    /// plain, unsynchronized `[String: Any]` dictionary — see `SessionRegistry.swift` for why.
    /// TCK-0230 / FND-0174: default TTL + entry cap (reap-on-access / LRU).
    private let sessionRegistry = SessionRegistry()
    /// Per-session defaults applied on respond/stream when params omit fields (TCK-0152).
    /// Unbounded: entries are removed with the owning session via `disposeSession`.
    private let sessionOverrides = SessionRegistry(maxEntries: nil, ttl: nil)
    /// Params ([String: Any], the same shape `createSession`/`sessionFor` build a native
    /// session from) used to construct each session, keyed by session id (TCK-0213 /
    /// FND-0156). `transitionSession` needs this to rebuild the SAME kind of native session
    /// (system / CoreAI / PCC) — `LanguageModelSession` exposes no way to introspect an
    /// existing instance's `model`/`tools`, so without this the daemon would have to guess
    /// (defaulting to the system branch) when recreating a session for a real transition.
    /// Unbounded: entries are removed with the owning session via `disposeSession`.
    private let sessionBuildParams = SessionRegistry(maxEntries: nil, ttl: nil)

    /// Test-only seam (TCK-0125 / FND-0088): when set, the MLX-direct-path generation methods
    /// (`generateTextMLXDirect`, `generateVisionTextMLXDirect`, `streamMLXDirect`,
    /// `streamVisionMLXDirect`) use this backend instead of constructing a real
    /// `MLXInferenceBackend()`, so their dispatch/error-mapping logic can be verified against a
    /// canned/fake backend without real MLX hardware or model files. Always `nil` in production.
    /// Stored as `Any` (like `sessions` above) to keep the property declaration
    /// framework-agnostic; downcast to `any InferenceBackend` only inside the macOS-27-gated call
    /// sites. `internal` (not `public`): invisible outside this package's own test target, which
    /// reaches it via `@testable import`.
    var mlxBackendOverride: Any?

    /// Test-only seam (TCK-0125 / FND-0088): same as `mlxBackendOverride`, for the
    /// CoreAI-direct-path (`generateTextCoreAIDirect`, `streamCoreAIDirect`).
    var coreaiBackendOverride: Any?

    public init() {}

    public func health() -> [String: Any] {
        let frameworkAvailable = foundationModelsAPISupported()
        let modelStatus = systemModelStatus()
        let macOSVersion = ProcessInfo.processInfo.operatingSystemVersionString

        let systemModelDep: [String: Any] = {
            var dep: [String: Any] = [
                "available": modelStatus.available
            ]
            if let reason = modelStatus.reason {
                dep["reason"] = reason
            }
            if let reasonCode = modelStatus.reasonCode {
                dep["reasonCode"] = reasonCode
            }
            return dep
        }()

        let dependencies: [String: Any] = [
            "foundationModelsFramework": [
                "available": frameworkAvailable
            ],
            "systemModel": systemModelDep,
            "macOS": [
                "version": macOSVersion
            ]
        ]

        // status is "degraded" when the Foundation Models framework or system
        // model is unavailable, but ok:true is preserved for liveness probes.
        let criticalDepsAvailable = frameworkAvailable && modelStatus.available
        let status = criticalDepsAvailable ? "ok" : "degraded"

        // TCK-0230 / FND-0174: make session-table pressure observable without a dump.
        var sessions: [String: Any] = [
            "count": sessionRegistry.count
        ]
        if let oldestAgeSeconds = sessionRegistry.oldestAgeSeconds {
            sessions["oldestAgeSeconds"] = oldestAgeSeconds
        }

        return [
            "ok": true,
            "version": "0.1.0",
            "status": status,
            "dependencies": dependencies,
            "sessions": sessions
        ]
    }

    public func availability() -> [String: Any] {
        let status = systemModelStatus()
        let pccStatus = pccModelStatus()
        var systemModel: [String: Any] = [
            "id": "apple.system",
            "available": status.available,
            "local": true,
                "supports": [
                    "text": true,
                    "image": multimodalInputSupported(),
                    "streaming": true,
                    "structuredOutput": structuredOutputSupported(),
                    "toolCalling": foundationModelsAPISupported(),
                    "tokenCounting": tokenCountingAPISupported(),
                    "contextWindow": foundationModelsAPISupported()
                ]
        ]

        if let reason = status.reason {
            systemModel["reason"] = reason
        }
        if let reasonCode = status.reasonCode {
            systemModel["reasonCode"] = reasonCode
        }

        // `supports` is MEASURED from the model's own `capabilities` when the SDK
        // exposes them (macOS 27+), and only falls back to literals below that
        // (TCK-0223 / FND-0155). The literals were previously unfalsifiable
        // assertions that would silently diverge from the SDK — and they omitted
        // `image`, so the TS provider rejected every image bound for apple.pcc
        // without ever asking the model.
        var pccSupports: [String: Any] = [
            "text": true,
            "streaming": true,
            "longContext": true,
            "tokenCounting": false,
            "contextWindow": true,
            "needsPcc": true
        ]
        if let measured = pccStatus.capabilities {
            for (key, value) in measured {
                pccSupports[key] = value
            }
        } else {
            // Pre-macOS-27 fallback: the capability API does not exist yet.
            pccSupports["structuredOutput"] = true
            pccSupports["toolCalling"] = true
            pccSupports["reasoning"] = true
        }

        var pccModel: [String: Any] = [
            "id": "apple.pcc",
            "available": pccStatus.available,
            "local": false,
            "capabilitiesSource": pccStatus.capabilities != nil ? "measured" : "asserted",
            "supports": pccSupports
        ]
        if let reason = pccStatus.reason {
            pccModel["reason"] = reason
        }
        if let reasonCode = pccStatus.reasonCode {
            pccModel["reasonCode"] = reasonCode
        }

        let coreAIModels = CoreAIModelRegistry.availabilityModels()
        var result: [String: Any] = [
            "available": status.available || pccStatus.available || coreAIModels.contains { JSON.bool($0, key: "available") == true },
            "models": [
                systemModel,
                pccModel
            ] + coreAIModels
        ]

        if let reason = status.reason {
            result["reason"] = reason
        }
        if let reasonCode = status.reasonCode {
            result["reasonCode"] = reasonCode
        }

        return result
    }

    public func capabilities() -> [String: Any] {
        let availabilityReport = availability()
        let pccStatus = pccModelStatus()

        var features: [String: Any] = [
            "textGeneration": true,
            "sessions": foundationModelsAPISupported(),
            "nativeStreaming": foundationModelsAPISupported(),
            "syntheticStreaming": false,
            "structuredOutput": structuredOutputSupported(),
            "toolCalling": foundationModelsAPISupported(),
            "tokenCounting": tokenCountingAPISupported(),
            "contextWindow": foundationModelsAPISupported(),
            "multimodalInput": multimodalInputSupported(),
            "privateCloudCompute": pccStatus.available,
            // Vision.framework OCR (VNRecognizeTextRequest). Gated on
            // Vision.framework availability; real entitlement check is deferred
            // to on-device smoke (TCK-0044). Barcode is a separate flag (TCK-0256).
            "visionOCR": visionOCRSupported(),
            // Vision.framework barcode detection (VNDetectBarcodesRequest).
            // Distinct from visionOCR so clients can feature-detect honestly
            // (TCK-0256 / FND-0238).
            "visionBarcode": visionBarcodeSupported(),
            // Streaming cancellation rides the native-streaming path
            // (generation.cancel + AbortSignal, TCK-0011).
            "cancellation": foundationModelsAPISupported()
        ]
        if let quota = pccStatus.quota {
            features["pccQuota"] = quota
        }

        return [
            "protocolVersion": 1,
            "targetProtocolVersion": 2,
            "daemon": [
                "version": "0.1.0"
            ],
            "features": features,
            "models": availabilityReport["models"] ?? []
        ]
    }

    public func countTokens(params: [String: Any]) async throws -> [String: Any] {
        if let modelId = JSON.string(params, key: "model"),
           CoreAIModelRegistry.isCoreAIModelId(modelId) {
            throw CoreAIModelRegistry.requestError(for: modelId)
        }

        // FND-0154 (TCK-0217) — reject BEFORE any measurement happens.
        //
        // Without this guard, requesting `model: "apple.pcc"` fell through to
        // the `#if canImport(FoundationModels)` branch below, which
        // unconditionally builds a `SystemLanguageModel` (`systemLanguageModel
        // (params:)` ignores `params["model"]` entirely) and calls
        // `model.tokenCount(for:)` on it — then labeled the result
        // `"model": "apple.pcc"` from the echoed request param. That is not an
        // imprecise PCC estimate; it is an on-device SYSTEM-MODEL token count
        // wearing a PCC label, handed to a caller that uses this number to
        // decide whether a prompt fits PCC's context window.
        //
        // There is no legitimate way to measure PCC's real token count instead:
        // `tokenCount(for:)` is declared only in an extension of
        // `SystemLanguageModel` (see the arm64e-apple-macos.swiftinterface,
        // `extension FoundationModels::SystemLanguageModel { ...
        // tokenCount(for:) ... }`, macOS 26.4+); `PrivateCloudComputeLanguageModel`
        // has no such method, and the shared `LanguageModel` protocol it
        // conforms to (`associatedtype Executor`, `capabilities`,
        // `executorConfiguration`) declares no token-counting requirement
        // either. `availability()` already advertises this via
        // `pccModel.supports.tokenCounting == false` (line ~138 below) — this
        // is that contract enforced at the call site instead of only declared.
        //
        // `-32020` (`.unsupported`), not `-32010` (`.modelUnavailable`):
        // this is not "PCC is down, try again" (which would use
        // `pcc_unavailable`/`pcc_device_not_eligible`/`pcc_system_not_ready`
        // from `pccModelStatus()`) — it is "this operation does not exist for
        // this model, on any hardware, ever." Mirrors the same
        // reject-before-fallthrough shape as the CoreAI branch immediately
        // above.
        if JSON.string(params, key: "model") == "apple.pcc" {
            throw JsonRpcError.unsupported(
                "Private Cloud Compute does not support token counting: " +
                    "PrivateCloudComputeLanguageModel has no tokenCount(for:) API " +
                    "(unlike SystemLanguageModel). Measuring the on-device system " +
                    "model instead and labeling the result \"apple.pcc\" would " +
                    "silently mislabel a system-model measurement as a PCC " +
                    "measurement, so this is rejected instead of measured wrong.",
                data: [
                    "code": "PCC_TOKEN_COUNTING_UNSUPPORTED",
                    "model": "apple.pcc",
                    "reasonCode": "pcc_token_counting_unsupported"
                ]
            )
        }

        let prompt = promptText(params: params)
        let status = systemModelStatus()
        guard status.available else {
            throw JsonRpcError.modelUnavailable(
                "Apple Foundation Models are unavailable.",
                data: [
                    "code": "APPLE_MODEL_UNAVAILABLE",
                    "reason": status.reason ?? "unknown",
                    "reasonCode": status.reasonCode ?? "unknown"
                ]
            )
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.4, *) {
            let model = try systemLanguageModel(params: params)
            // Native tokenizer per component (input, instructions, tools, schema).
            let inputTokens = try await model.tokenCount(for: prompt)

            var instructionsTokens: Int?
            if let instructions = JSON.string(params, key: "instructions"), !instructions.isEmpty {
                instructionsTokens = try await model.tokenCount(for: instructions)
            }

            var toolTokens: Int?
            if let toolsText = toolsTokenText(params: params) {
                toolTokens = try await model.tokenCount(for: toolsText)
            }

            var schemaTokens: Int?
            if let schemaText = schemaTokenText(params: params) {
                schemaTokens = try await model.tokenCount(for: schemaText)
            }

            let totalTokens = inputTokens
                + (instructionsTokens ?? 0)
                + (toolTokens ?? 0)
                + (schemaTokens ?? 0)
            let contextWindowTokens = model.contextSize

            var result: [String: Any] = [
                "inputTokens": inputTokens,
                "totalTokens": totalTokens,
                "contextWindowTokens": contextWindowTokens,
                "remainingTokens": max(0, contextWindowTokens - totalTokens),
                "estimated": false,
                "model": JSON.string(params, key: "model") ?? "apple.system",
                "traceId": "trc_swift_\(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: ""))"
            ]
            if let instructionsTokens { result["instructionsTokens"] = instructionsTokens }
            if let toolTokens { result["toolTokens"] = toolTokens }
            if let schemaTokens { result["schemaTokens"] = schemaTokens }
            return result
        }
        #endif

        throw JsonRpcError.modelUnavailable(
            "Apple Foundation Models token counting requires macOS 26.4 or newer.",
            data: ["code": "UNSUPPORTED_PLATFORM"]
        )
    }

    /// Stable text used to count token cost of tool definitions (name + description + input schema),
    /// without constructing native `Tool` objects (which would require the callback bridge).
    private func toolsTokenText(params: [String: Any]) -> String? {
        guard let tools = JSON.array(params, key: "tools"), !tools.isEmpty else {
            return nil
        }
        return tools.map { jsonText($0) }.joined(separator: "\n")
    }

    /// Stable text used to count token cost of the `json_schema` response format.
    private func schemaTokenText(params: [String: Any]) -> String? {
        let responseFormat = JSON.object(params, key: "responseFormat") ?? [:]
        guard JSON.string(responseFormat, key: "type") == "json_schema",
              let schema = responseFormat["schema"] else {
            return nil
        }
        return jsonText(schema)
    }

    private func jsonText(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return text
    }

    public func createSession(params: [String: Any]) throws -> [String: Any] {
        if hasCallbackTools(params: params) {
            throw callbackToolsRequireStreamingError(params: params)
        }

        if let modelId = JSON.string(params, key: "model"),
           CoreAIModelRegistry.isCoreAIModelId(modelId) {
            #if canImport(FoundationModels)
            if #available(macOS 27.0, *) {
                let sessionId = JSON.string(params, key: "sessionId") ?? "ses_swift_\(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: ""))"
                let session = try makeSession(params: params, transcript: try Self.historyTranscript(params: params))
                sessionRegistry.set(sessionId, session)
                sessionBuildParams.set(sessionId, params)

                return [
                    "sessionId": sessionId,
                    "model": modelId,
                    "traceId": "trc_swift_\(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: ""))"
                ]
            }
            #endif

            throw CoreAIModelRegistry.requestError(for: modelId)
        }

        let status = systemModelStatus()
        guard status.available else {
            throw JsonRpcError.modelUnavailable(
                "Apple Foundation Models are unavailable.",
                data: [
                    "code": "APPLE_MODEL_UNAVAILABLE",
                    "reason": status.reason ?? "unknown",
                    "reasonCode": status.reasonCode ?? "unknown"
                ]
            )
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let sessionId = JSON.string(params, key: "sessionId") ?? "ses_swift_\(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: ""))"
            let session = try makeSession(params: params, transcript: try Self.historyTranscript(params: params))
            sessionRegistry.set(sessionId, session)
            sessionBuildParams.set(sessionId, params)

            return [
                "sessionId": sessionId,
                "model": JSON.string(params, key: "model") ?? "apple.system",
                "traceId": "trc_swift_\(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: ""))"
            ]
        }
        #endif

        throw JsonRpcError.modelUnavailable(
            "Apple Foundation Models require macOS 26 or newer.",
            data: ["code": "UNSUPPORTED_PLATFORM"]
        )
    }

    public func disposeSession(params: [String: Any]) throws -> [String: Any] {
        guard let sessionId = JSON.string(params, key: "sessionId") else {
            throw JsonRpcError.invalidRequest("sessionId is required.")
        }

        let disposed = sessionRegistry.remove(sessionId)
        sessionOverrides.remove(sessionId)
        sessionBuildParams.remove(sessionId)
        return [
            "sessionId": sessionId,
            "disposed": disposed
        ]
    }

    /// Transitions a session's instructions (TCK-0213 / FND-0156).
    ///
    /// The SDK 27 surface exposes no setter for `LanguageModelSession`'s
    /// instructions — once a native session is built, its instructions entry is
    /// fixed. The only honest way to change it for an IN-FLIGHT session is to
    /// recreate the native session, preserving the prior conversation via
    /// `LanguageModelSession(model:tools:transcript:)` (confirmed in the SDK 27
    /// `.swiftinterface`, `FoundationModels.LanguageModelSession` extension) and
    /// folding the new instructions into that preserved transcript.
    ///
    /// Previously this returned `transitioned: true` whenever a session existed
    /// for `sessionId`, but only ever wrote to a side-table (`sessionOverrides`)
    /// that `sessionFor` never re-reads for an ALREADY-registered session — i.e.
    /// it claimed success in exactly the case where nothing observable changed.
    /// `transitioned` now reflects whether the native session was actually
    /// rebuilt with the new instructions.
    ///
    /// `profile` alone carries no instructions text at this layer — profile →
    /// instructions resolution happens client-side
    /// (`RuntimeFoundationModelsSession.applyProfile`, `packages/foundationmodels/src/runtime.ts`)
    /// before a request reaches the daemon. A `profile`-only transition with no
    /// accompanying `instructions` string is recorded (so a future
    /// dispose+recreate for this `sessionId` can still pick it up via
    /// `mergeSessionOverrides`) but cannot be materialized on the CURRENTLY live
    /// session, and is honestly reported as `transitioned: false`.
    public func transitionSession(params: [String: Any]) throws -> [String: Any] {
        guard let sessionId = JSON.string(params, key: "sessionId") else {
            throw JsonRpcError.invalidRequest("sessionId is required.")
        }

        let profile = JSON.string(params, key: "profile")
        let instructions = JSON.string(params, key: "instructions")
        guard profile != nil || instructions != nil else {
            throw JsonRpcError.invalidRequest("profile or instructions is required.")
        }

        guard let existing = sessionRegistry.get(sessionId) else {
            return [
                "transitioned": false,
                "provider": "apple"
            ]
        }

        var overrides = sessionOverrides.get(sessionId) as? [String: String] ?? [:]
        if let profile {
            overrides["profile"] = profile
        }
        if let instructions {
            overrides["instructions"] = instructions
        }
        sessionOverrides.set(sessionId, overrides)

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *),
           let instructions,
           let existingSession = existing as? LanguageModelSession {
            let buildParams = (sessionBuildParams.get(sessionId) as? [String: Any]) ?? params
            let rebuildModelId = JSON.string(buildParams, key: "model")
            // Mirrors the pre-flight availability convention used everywhere else in
            // this file for the system branch (`createSession`, `generateText`,
            // `stream`): checked BEFORE construction, never relied on the SDK's own
            // error path, because Swift `try/catch` cannot intercept a
            // `fatalError`/`preconditionFailure`. CoreAI/PCC branches keep their own
            // guards inside `buildSession`/`pccLanguageModel`, so this only applies
            // when the session being rebuilt is (or defaults to) the system model.
            let isSystemModel = rebuildModelId == nil || rebuildModelId == "apple.system"
            if isSystemModel, !systemModelStatus().available {
                return [
                    "transitioned": false,
                    "provider": "apple"
                ]
            }

            var rebuildParams = buildParams
            rebuildParams["instructions"] = instructions
            // A rebuilt session is a fresh construction: it must NOT inherit the
            // one-shot `history` seed from the original create call, which would
            // otherwise be prepended a second time ahead of the preserved
            // `existingSession.transcript` below.
            rebuildParams.removeValue(forKey: "history")

            let rebuiltTranscript = Self.rebuildTranscript(existingSession.transcript, replacingInstructionsWith: instructions)
            let rebuilt = try buildSession(params: rebuildParams, transcript: rebuiltTranscript)
            try applyTranscriptErrorHandlingPolicy(to: rebuilt, params: rebuildParams)

            sessionRegistry.set(sessionId, rebuilt)
            sessionBuildParams.set(sessionId, rebuildParams)

            return [
                "transitioned": true,
                "provider": "apple"
            ]
        }
        #endif

        return [
            "transitioned": false,
            "provider": "apple"
        ]
    }

    /// Prewarms the native runtime for a model (best-effort; TCK-0152).
    public func prewarmSession(params: [String: Any]) async throws -> [String: Any] {
        let traceId = makeTraceId()
        let modelId = JSON.string(params, key: "model") ?? "apple.system"

        if CoreAIModelRegistry.isCoreAIModelId(modelId) {
            #if canImport(FoundationModels)
            if #available(macOS 27.0, *) {
                guard let registeredModel = CoreAIModelRegistry.model(id: modelId) else {
                    throw CoreAIModelRegistry.requestError(for: modelId)
                }

                let backend: any InferenceBackend
                if modelId.hasPrefix("apple.mlx:") {
                    backend = MLXInferenceBackend()
                } else if modelId.hasPrefix("apple.coreai:") {
                    backend = CoreAIInferenceBackend()
                } else {
                    return [
                        "warmed": false,
                        "model": modelId,
                        "traceId": traceId
                    ]
                }

                await backend.prewarm(
                    modelId: modelId,
                    registryPath: registeredModel.path,
                    transcript: Transcript()
                )

                return [
                    "warmed": true,
                    "model": modelId,
                    "traceId": traceId
                ]
            }
            #endif

            throw CoreAIModelRegistry.requestError(for: modelId)
        }

        // apple.system (TCK-0213 / FND-0161): previously this branch reported
        // `warmed: status.available` without ever touching the runtime — a
        // session-less device could be "available" (framework present, model
        // eligible) yet nothing was ever warmed. Build/obtain the real native
        // session and call the SDK's own `LanguageModelSession.prewarm(promptPrefix:)`
        // (confirmed in the SDK 27 `.swiftinterface`: available since macOS 26.0,
        // no CoreAI/PCC involvement). `apple.pcc` and any other non-CoreAI model id
        // are out of scope here (FRONTEIRA: PCC construction belongs to the
        // parallel executor) and keep the prior best-effort, honestly-labeled
        // fallback below.
        //
        // The `systemModelStatus().available` guard runs BEFORE touching the SDK,
        // mirroring `createSession`/`generateText`/`stream` elsewhere in this file
        // (never relying on the SDK's own unavailable-path here, same rationale as
        // the PCC entitlement pre-check at `pccLanguageModel()`: Swift `try/catch`
        // cannot intercept a `fatalError`/`preconditionFailure`, so a device-level
        // ineligibility must be ruled out ahead of construction, not caught after).
        if modelId == "apple.system" {
            let status = systemModelStatus()
            guard status.available else {
                return [
                    "warmed": false,
                    "model": modelId,
                    "traceId": traceId
                ]
            }

            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                do {
                    // `sessionFor` builds/registers a fresh session when `sessionId` is
                    // new (also tracking its build params for a later transition) or
                    // reuses the already-registered one for an existing id — "obtenha"
                    // per FND-0161.
                    let session = try sessionFor(params: params, toolBridge: nil)
                    session.prewarm()
                    return [
                        "warmed": true,
                        "model": modelId,
                        "traceId": traceId
                    ]
                } catch {
                    return [
                        "warmed": false,
                        "model": modelId,
                        "traceId": traceId
                    ]
                }
            }
            #endif

            return [
                "warmed": false,
                "model": modelId,
                "traceId": traceId
            ]
        }

        // VER-20260801-230000 (D1): this fallback used to call
        // `systemModelStatus()` for EVERY non-system model id — including
        // `apple.pcc`, whose availability is a different question with a
        // different answer. `{warmed: true, model: "apple.pcc"}` built from the
        // system model's status is the same defect FND-0154 called the worst
        // kind: a right-looking value under the wrong label. Prose in
        // docs/protocol.md disclosed it, but the wire payload still misled
        // anyone reading the field instead of the spec.
        //
        // PCC has no prewarm we can call, so the honest answer is `false` — not
        // another model's availability wearing PCC's name.
        if modelId == "apple.pcc" {
            return [
                "warmed": false,
                "model": modelId,
                "reason": "prewarm is not available for apple.pcc; no native prewarm exists on PrivateCloudComputeLanguageModel",
                "traceId": traceId
            ]
        }
        let status = systemModelStatus()
        return [
            "warmed": status.available,
            "model": modelId,
            "traceId": traceId
        ]
    }

    private func makeTraceId() -> String {
        "trc_swift_\(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: ""))"
    }

    private func mergeSessionOverrides(into params: [String: Any]) -> [String: Any] {
        guard let sessionId = JSON.string(params, key: "sessionId"),
              let overrides = sessionOverrides.get(sessionId) as? [String: String] else {
            return params
        }

        var merged = params
        if merged["instructions"] == nil, let instructions = overrides["instructions"] {
            merged["instructions"] = instructions
        }
        if merged["profile"] == nil, let profile = overrides["profile"] {
            merged["profile"] = profile
        }
        return merged
    }

    /// Performs OCR on a base64-encoded image using Vision.framework's
    /// `VNRecognizeTextRequest`. Params must contain `"base64"` (the raw base64
    /// image bytes, no data-URL prefix) and optionally `"mimeType"`.
    /// Returns `{ "texts": [String] }`.
    public func visionOCR(params: [String: Any]) async throws -> [String: Any] {
        guard visionOCRSupported() else {
            throw JsonRpcError.unsupported(
                "Vision.framework is not available on this platform.",
                data: ["code": "VISION_OCR_UNAVAILABLE"]
            )
        }
        return try await performOCR(params: params)
    }

    /// Detects barcodes in a base64-encoded image using Vision.framework's
    /// `VNDetectBarcodesRequest`. Params must contain `"base64"` and optionally
    /// `"mimeType"`. Returns `{ "barcodes": [{ "symbology": String, "value": String }] }`.
    /// Unavailable → `VISION_BARCODE_UNAVAILABLE` (TCK-0256 / FND-0238).
    public func visionBarcode(params: [String: Any]) async throws -> [String: Any] {
        guard visionBarcodeSupported() else {
            throw JsonRpcError.unsupported(
                "Vision.framework barcode detection is not available on this platform.",
                data: ["code": "VISION_BARCODE_UNAVAILABLE"]
            )
        }
        return try await performBarcodeDetection(params: params)
    }

    /// Logs a feedback attachment for a native session via
    /// `LanguageModelSession.logFeedbackAttachment(sentiment:issues:desiredResponseText:)`
    /// (TCK-0201). Params: `sessionId` (required), `sentiment` (optional:
    /// "positive" | "negative" | "neutral"), `issues` (optional array of
    /// `{ "category", "explanation"? }`) and `desiredResponseText` (optional string).
    /// Unknown sentiment/category values fail fast with -32600 before any session
    /// lookup. Returns `{ "attachmentBase64": String }` — the native `Data`
    /// attachment, base64-encoded, ready to attach to a Feedback Assistant report.
    ///
    /// Uses the `desiredResponseText` overload rather than `desiredOutput:
    /// Transcript.Entry?`: transcript entries are not JSON-serializable across the
    /// bridge, and the text overload is itself a thin native wrapper that builds the
    /// transcript entry from the string (SDK 27.0 swiftinterface).
    public func logFeedbackAttachment(params: [String: Any]) throws -> [String: Any] {
        guard let sessionId = JSON.string(params, key: "sessionId") else {
            throw JsonRpcError.invalidRequest("sessionId is required.")
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let sentiment = try feedbackSentiment(params: params)
            let issues = try feedbackIssues(params: params)

            guard let session = sessionRegistry.get(sessionId) as? LanguageModelSession else {
                throw JsonRpcError.invalidRequest("No native session found for sessionId \"\(sessionId)\".")
            }

            let attachment = session.logFeedbackAttachment(
                sentiment: sentiment,
                issues: issues,
                desiredResponseText: JSON.string(params, key: "desiredResponseText")
            )
            return ["attachmentBase64": attachment.base64EncodedString()]
        }
        #endif

        throw JsonRpcError.unsupported(
            "Feedback attachments require macOS 26 or newer with the Foundation Models framework.",
            data: ["code": "FEEDBACK_ATTACHMENT_UNAVAILABLE"]
        )
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func feedbackSentiment(params: [String: Any]) throws -> LanguageModelFeedback.Sentiment? {
        guard let raw = JSON.string(params, key: "sentiment") else {
            return nil
        }
        switch raw {
        case "positive": return .positive
        case "negative": return .negative
        case "neutral": return .neutral
        default:
            throw JsonRpcError.invalidRequest(
                "Unknown feedback sentiment \"\(raw)\". Expected one of: positive, negative, neutral."
            )
        }
    }

    @available(macOS 26.0, *)
    private func feedbackIssues(params: [String: Any]) throws -> [LanguageModelFeedback.Issue] {
        guard let rawIssues = JSON.array(params, key: "issues") else {
            return []
        }
        return try rawIssues.map { raw in
            guard let category = JSON.string(raw, key: "category") else {
                throw JsonRpcError.invalidRequest("Feedback issue category is required.")
            }
            return LanguageModelFeedback.Issue(
                category: try feedbackIssueCategory(category),
                explanation: JSON.string(raw, key: "explanation")
            )
        }
    }

    @available(macOS 26.0, *)
    private func feedbackIssueCategory(_ raw: String) throws -> LanguageModelFeedback.Issue.Category {
        switch raw {
        case "unhelpful": return .unhelpful
        case "tooVerbose": return .tooVerbose
        case "didNotFollowInstructions": return .didNotFollowInstructions
        case "incorrect": return .incorrect
        case "stereotypeOrBias": return .stereotypeOrBias
        case "suggestiveOrSexual": return .suggestiveOrSexual
        case "vulgarOrOffensive": return .vulgarOrOffensive
        case "triggeredGuardrailUnexpectedly": return .triggeredGuardrailUnexpectedly
        default:
            throw JsonRpcError.invalidRequest(
                "Unknown feedback issue category \"\(raw)\". Expected one of: unhelpful, tooVerbose, didNotFollowInstructions, incorrect, stereotypeOrBias, suggestiveOrSexual, vulgarOrOffensive, triggeredGuardrailUnexpectedly."
            )
        }
    }
    #endif

    public func respond(params: [String: Any], toolBridge: Any?) async throws -> [String: Any] {
        let params = mergeSessionOverrides(into: params)
        // Respond-path callback policy (TCK-0015c): the callback bridge needs the
        // duplex stream socket (tool_call_request out, tools.result in). A plain
        // request/response respond cannot host it, so callback tools fail fast
        // with the typed -32020 TOOL_CALLBACKS_REQUIRE_STREAMING error. Static
        // tools (staticOutput, callback:false) remain fully supported here.
        if toolBridge == nil, hasCallbackTools(params: params) {
            throw callbackToolsRequireStreamingError(params: params)
        }

        let responseFormat = JSON.object(params, key: "responseFormat")
        let prompt = promptText(params: params)
        let output: Any
        // FND-0157/FND-0162 (TCK-0220): nil here means "no native usage available for this
        // path" — the MLX-/CoreAI-direct branches below bypass `LanguageModelSession` entirely
        // and can never produce it, regardless of macOS version. The session-backed branches
        // (generateText/generateStructuredOutput/generateMultimodalText) always fill this in,
        // themselves falling back to the word-count estimator (`estimated:true`) pre-macOS-27.
        var usage: [String: Any]?

        if let mlxModelId = JSON.string(params, key: "model"), mlxModelId.hasPrefix("apple.mlx:") {
            try rejectSessionOnlyOptions(params: params, modelId: mlxModelId)
            // MLX-direct-path (ADR-0006 / DES-0051): dispatch `apple.mlx:*` straight to the
            // backend and return the generated text over our JSON-RPC, bypassing
            // `LanguageModelSession` (whose channel event inits are sealed on the SDK 27 beta).
            // Streaming, structured output and multimodal are out of scope → typed errors.
            if JSON.string(responseFormat ?? [:], key: "type") == "json_schema" {
                // Structured output with images is unsupported for ALL MLX models — reject FIRST so an
                // {image + json_schema} request cannot bypass this check via the vision route.
                if hasImageParts(params: params) {
                    throw JsonRpcError.modelUnavailable(
                        "Structured output (json_schema) with multimodal input is not supported for MLX models (\(mlxModelId)).",
                        data: [
                            "code": "STRUCTURED_OUTPUT_UNAVAILABLE",
                            "model": mlxModelId,
                            "reasonCode": "mlx_structured_multimodal_unsupported"
                        ]
                    )
                }
                output = try await generateStructuredOutputMLXDirect(
                    prompt: prompt,
                    params: params,
                    modelId: mlxModelId
                )
            } else if hasImageParts(params: params) {
                // VLM (TCK-0109): a vision-capable model (registry backend "mlx-vlm") routes image
                // parts to the VLM path; a text-only MLX model rejects images with a typed error.
                if CoreAIModelRegistry.model(id: mlxModelId)?.backend == "mlx-vlm" {
                    output = try await generateVisionTextMLXDirect(prompt: prompt, params: params, modelId: mlxModelId)
                } else {
                    throw JsonRpcError.modelUnavailable(
                        "Multimodal input is not supported for MLX model \(mlxModelId) (text-only; register a vision model with backend \"mlx-vlm\").",
                        data: [
                            "code": "MULTIMODAL_INPUT_UNAVAILABLE",
                            "model": mlxModelId,
                            "reasonCode": "mlx_multimodal_unsupported"
                        ]
                    )
                }
            } else {
                output = try await generateTextMLXDirect(prompt: prompt, params: params, modelId: mlxModelId)
            }
        } else if let coreaiModelId = JSON.string(params, key: "model"), coreaiModelId.hasPrefix("apple.coreai:") {
            try rejectSessionOnlyOptions(params: params, modelId: coreaiModelId)
            // CoreAI-direct-path (ADR-0007): apple.coreai:* generates via the CoreAILanguageModels
            // runtime and returns text over JSON-RPC, bypassing the sealed channel (same pattern as MLX).
            // Structured output + multimodal are out of scope → typed errors.
            if hasImageParts(params: params) {
                throw JsonRpcError.modelUnavailable(
                    "Multimodal input is not supported for CoreAI models (\(coreaiModelId)).",
                    data: [
                        "code": "MULTIMODAL_INPUT_UNAVAILABLE",
                        "model": coreaiModelId,
                        "reasonCode": "coreai_multimodal_unsupported"
                    ]
                )
            }
            if JSON.string(responseFormat ?? [:], key: "type") == "json_schema" {
                throw JsonRpcError.modelUnavailable(
                    "Structured output (json_schema) is not supported for CoreAI models (\(coreaiModelId)). Use plain text generation.",
                    data: [
                        "code": "STRUCTURED_OUTPUT_UNAVAILABLE",
                        "model": coreaiModelId,
                        "reasonCode": "coreai_structured_unsupported"
                    ]
                )
            }
            output = try await generateTextCoreAIDirect(prompt: prompt, params: params, modelId: coreaiModelId)
        } else {
            // TCK-0224 / FND-0129 — the native (`apple.system` / AFM) route is decided
            // by `nativeRoute(params:)` and nowhere else, so `respond` and `stream`
            // cannot disagree about how image parts and `json_schema` combine.
            //
            // FND-0157/FND-0162 (TCK-0220): every case captures `usage` alongside
            // `output` from the same tuple-returning generator, so real native usage
            // (or its word-count fallback pre-macOS-27) reaches the JSON-RPC response
            // no matter which route fired.
            //
            // TCK-0279 / FND-0216: when Attachment symbols are unbound, do NOT fall
            // through the multimodalSupported:false degrade (silent image drop →
            // text). That would false-PASS smokes and hide the SDK↔OS skew. Fail
            // closed with MULTIMODAL_INPUT_UNAVAILABLE instead of SIGSEGV.
            try rejectUnavailableAttachmentIfNeeded(params: params)
            switch nativeRoute(params: params) {
            case .text:
                let result = try await generateText(prompt: prompt, params: params, toolBridge: toolBridge)
                output = result.text
                usage = result.usage
            case .structured:
                let result = try await generateStructuredOutput(prompt: prompt, params: params, toolBridge: toolBridge)
                output = result.output
                usage = result.usage
            case .multimodal:
                let result = try await generateMultimodalText(params: params, toolBridge: toolBridge)
                output = result.text
                usage = result.usage
            case .multimodalStructured:
                let result = try await generateMultimodalStructuredOutput(params: params, toolBridge: toolBridge)
                output = result.output
                usage = result.usage
            }
        }
        let outputText = textForTokenEstimate(output)

        return [
            "output": output,
            "model": JSON.string(params, key: "model") ?? "apple.system",
            "usage": usage ?? estimatedUsageDict(prompt: prompt, outputText: outputText),
            "traceId": "trc_swift_\(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: ""))"
        ]
    }

    public func stream(params: [String: Any], toolBridge: Any?, emit: @escaping ([String: Any]) async throws -> Void) async throws {
        let params = mergeSessionOverrides(into: params)

        let prompt = promptText(params: params)
        let traceId = "trc_swift_\(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: ""))"

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            // MLX-direct streaming (ADR-0006 follow-up / TCK-0106): emit real deltas from the
            // mlx-swift-lm decode loop, bypassing LanguageModelSession / the sealed channel.
            if let mlxModelId = JSON.string(params, key: "model"), mlxModelId.hasPrefix("apple.mlx:") {
                try rejectSessionOnlyOptions(params: params, modelId: mlxModelId)
                try await streamMLXDirect(params: params, prompt: prompt, modelId: mlxModelId, traceId: traceId, emit: emit)
                return
            }

            // CoreAI-direct streaming (ADR-0007): apple.coreai:* streams via the Apple
            // LanguageModelSession.streamResponse of the CoreAILanguageModels model, bypassing the
            // custom executor / sealed channel.
            if let coreaiModelId = JSON.string(params, key: "model"), coreaiModelId.hasPrefix("apple.coreai:") {
                try rejectSessionOnlyOptions(params: params, modelId: coreaiModelId)
                try await streamCoreAIDirect(params: params, prompt: prompt, modelId: coreaiModelId, traceId: traceId, emit: emit)
                return
            }

            if !CoreAIModelRegistry.isCoreAIModelId(JSON.string(params, key: "model")) {
                let status = systemModelStatus()
                guard status.available else {
                    throw JsonRpcError.modelUnavailable(
                        "Apple Foundation Models are unavailable.",
                        data: [
                            "code": "APPLE_MODEL_UNAVAILABLE",
                            "reason": status.reason ?? "unknown",
                            "reasonCode": status.reasonCode ?? "unknown"
                        ]
                    )
                }
            }

            let session = try sessionFor(params: params, toolBridge: toolBridge)
            let options = try generationOptions(params: params)

            // TCK-0224 / FND-0129 — same single decision as `respond`, so the two
            // entry points route an identical request identically by construction.
            // TCK-0279 / FND-0216: same Attachment-symbol fail-closed as respond.
            try rejectUnavailableAttachmentIfNeeded(params: params)
            switch nativeRoute(params: params) {
            case .text:
                try await streamText(
                    params: params,
                    prompt: prompt,
                    traceId: traceId,
                    session: session,
                    options: options,
                    emit: emit
                )
            case .structured:
                try await streamStructuredOutput(
                    params: params,
                    prompt: prompt,
                    traceId: traceId,
                    session: session,
                    options: options,
                    emit: emit
                )
            case .multimodal:
                try await streamMultimodalText(params: params, toolBridge: toolBridge, traceId: traceId, emit: emit)
            case .multimodalStructured:
                try await streamMultimodalStructuredOutput(
                    params: params,
                    toolBridge: toolBridge,
                    traceId: traceId,
                    emit: emit
                )
            }
            return
        }
        #endif

        throw JsonRpcError.modelUnavailable(
            "Apple Foundation Models require macOS 26 or newer.",
            data: ["code": "UNSUPPORTED_PLATFORM"]
        )
    }

    /// Text-only streaming over the native session (`NativeRoute.text`).
    ///
    /// Extracted from `stream(params:toolBridge:emit:)` in TCK-0224 so every
    /// native route is a single call from the one `switch nativeRoute(params:)`.
    /// Behaviour is unchanged: delta → result → done, `contextOptions` honoured.
    ///
    /// FND-0157 (TCK-0220): `ResponseStream.Snapshot.usage` (macOS 27+) is cumulative per
    /// snapshot; the last snapshot's usage is the final count for the turn.
    @available(macOS 26.0, *)
    private func streamText(
        params: [String: Any],
        prompt: String,
        traceId: String,
        session: LanguageModelSession,
        options: GenerationOptions,
        emit: ([String: Any]) async throws -> Void
    ) async throws {
        var output = ""
        var lastUsage: [String: Any]?
        let stream: LanguageModelSession.ResponseStream<String>
        if let contextParams = try contextOptionsParams(params: params) {
            guard #available(macOS 27.0, *) else {
                throw contextOptionsUnavailableError()
            }
            stream = session.streamResponse(
                to: prompt,
                options: options,
                contextOptions: nativeContextOptions(contextParams)
            )
        } else {
            stream = session.streamResponse(to: prompt, options: options)
        }

        do {
            for try await snapshot in stream {
                // Cooperative cancellation (TCK-0011): stop emitting as soon as
                // the generation task is cancelled, even if the native stream
                // has more snapshots buffered.
                try Task.checkCancellation()

                if #available(macOS 27.0, *) {
                    lastUsage = usageDict(from: snapshot.usage)
                }

                let next = snapshot.content
                let delta = textDelta(previous: output, next: next)
                output = next

                if !delta.isEmpty {
                    try await emit(["type": "delta", "text": delta])
                }
            }
        } catch {
            throw mapNativeGenerationError(error, params: params)
        }

        try Task.checkCancellation()
        try await emit([
            "type": "result",
            "response": [
                "output": output,
                "model": JSON.string(params, key: "model") ?? "apple.system",
                "usage": lastUsage ?? estimatedUsageDict(prompt: prompt, outputText: output),
                "traceId": traceId
            ]
        ])
        try await emit(["type": "done"])
    }

    @available(macOS 26.0, *)
    private func streamStructuredOutput(
        params: [String: Any],
        prompt: String,
        traceId: String,
        session: LanguageModelSession,
        options: GenerationOptions,
        emit: ([String: Any]) async throws -> Void
    ) async throws {
        let responseFormat = JSON.object(params, key: "responseFormat") ?? [:]
        // TCK-0208: native `GenerationSchema.SchemaError` must reach the
        // contract mapper too, not just generation-time errors. The mapper
        // passes our own typed `JsonRpcError`s (the JSON-Schema bridge's
        // `UNSUPPORTED_SCHEMA_TYPE`) through untouched.
        let schema: GenerationSchema
        do {
            schema = try generationSchema(from: responseFormat["schema"])
        } catch {
            throw mapNativeGenerationError(error, params: params)
        }
        let stream: LanguageModelSession.ResponseStream<GeneratedContent>
        if let contextParams = try contextOptionsParams(params: params) {
            guard #available(macOS 27.0, *) else {
                throw contextOptionsUnavailableError()
            }
            stream = session.streamResponse(
                to: prompt,
                schema: schema,
                options: options,
                contextOptions: nativeContextOptions(contextParams, includeSchemaInPromptDefault: true)
            )
        } else {
            stream = session.streamResponse(to: prompt, schema: schema, includeSchemaInPrompt: true, options: options)
        }

        try await consumeStructuredStream(
            stream: stream,
            params: params,
            promptForTokens: prompt,
            traceId: traceId,
            emit: emit
        )
    }

    /// Drains a guided-generation stream into the wire event format shared by
    /// every structured route: deduplicated `structured_delta` snapshots, then
    /// `result`, then `done`.
    ///
    /// TCK-0224 — extracted from `streamStructuredOutput` so the text-prompt and
    /// multimodal-prompt variants cannot drift apart in the events they emit.
    /// `promptForTokens` is the text used for the input-token estimate: the
    /// plain prompt for the text route, `textOnlyPrompt(from:)` for the
    /// multimodal one (same convention as `streamMultimodalText`).
    ///
    /// TCK-0257 / FND-0239 — dedupe by raw JSON string identity (`RawJSONEmitTracker`)
    /// so identical cumulative snapshots skip `JSONSerialization` parse + the old
    /// double sortedKeys serialize equality path (O(n²) on long guided streams).
    @available(macOS 26.0, *)
    private func consumeStructuredStream(
        stream: LanguageModelSession.ResponseStream<GeneratedContent>,
        params: [String: Any],
        promptForTokens: String,
        traceId: String,
        emit: ([String: Any]) async throws -> Void
    ) async throws {
        var tracker = StreamingDelta.RawJSONEmitTracker()
        // FND-0157 (TCK-0220): see `stream()` — last snapshot's usage wins.
        var lastUsage: [String: Any]?
        do {
            for try await snapshot in stream {
                try Task.checkCancellation()

                if #available(macOS 27.0, *) {
                    lastUsage = usageDict(from: snapshot.usage)
                }

                let raw = snapshot.rawContent.jsonString
                guard let object = try tracker.consider(
                    rawJSON: raw,
                    parse: { rawJSON in try self.parseStructuredJSONString(rawJSON) }
                ) else {
                    continue
                }

                try await emit(["type": "structured_delta", "object": object])
            }
        } catch {
            throw mapNativeGenerationError(error, params: params)
        }

        try Task.checkCancellation()
        let finalObject = tracker.lastObject ?? NSNull()
        try await emit([
            "type": "result",
            "response": [
                "output": finalObject,
                "model": JSON.string(params, key: "model") ?? "apple.system",
                "usage": lastUsage ?? estimatedUsageDict(prompt: promptForTokens, outputText: textForTokenEstimate(finalObject)),
                "traceId": traceId
            ]
        ])
        try await emit(["type": "done"])
    }

    /// Parses a guided-generation JSON snapshot string. Empty → nil (skip tick).
    private func parseStructuredJSONString(_ raw: String) throws -> Any? {
        let data = Data(raw.utf8)
        guard !data.isEmpty else {
            return nil
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    @available(macOS 26.0, *)
    private func parseStructuredSnapshot(
        _ snapshot: LanguageModelSession.ResponseStream<GeneratedContent>.Snapshot
    ) throws -> Any? {
        try parseStructuredJSONString(snapshot.rawContent.jsonString)
    }

    private func jsonValuesEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        // Kept for any non-stream call sites; stream paths use StreamingDelta trackers
        // (TCK-0257) which avoid re-serializing both sides every tick.
        guard let lhsData = StreamingDelta.canonicalJSONData(lhs),
              let rhsData = StreamingDelta.canonicalJSONData(rhs) else {
            return false
        }
        return lhsData == rhsData
    }

    /// Returns the parsed JSON object plus its usage payload (FND-0157/FND-0162, TCK-0220): native
    /// `response.usage` when the native `respond` overload reached is macOS 27+, the word-count
    /// fallback (`estimated:true`) otherwise.
    private func generateStructuredOutput(
        prompt: String,
        params: [String: Any],
        toolBridge: Any?
    ) async throws -> (output: Any, usage: [String: Any]) {
        if !CoreAIModelRegistry.isCoreAIModelId(JSON.string(params, key: "model")) {
            let status = systemModelStatus()
            guard status.available else {
                throw JsonRpcError.modelUnavailable(
                    "Apple Foundation Models are unavailable.",
                    data: [
                        "code": "APPLE_MODEL_UNAVAILABLE",
                        "reason": status.reason ?? "unknown",
                        "reasonCode": status.reasonCode ?? "unknown"
                    ]
                )
            }
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let responseFormat = JSON.object(params, key: "responseFormat") ?? [:]
            // TCK-0208: see `streamStructuredOutput` — schema compilation
            // errors go through the contract mapper too.
            let schema: GenerationSchema
            do {
                schema = try generationSchema(from: responseFormat["schema"])
            } catch {
                throw mapNativeGenerationError(error, params: params)
            }
            let session = try sessionFor(params: params, toolBridge: toolBridge)
            let options = try generationOptions(params: params)
            do {
                if let contextParams = try contextOptionsParams(params: params) {
                    guard #available(macOS 27.0, *) else {
                        throw contextOptionsUnavailableError()
                    }
                    let response = try await session.respond(
                        to: prompt,
                        schema: schema,
                        options: options,
                        contextOptions: nativeContextOptions(contextParams, includeSchemaInPromptDefault: true)
                    )
                    let output = try jsonObject(fromGeneratedContent: response.content)
                    return (output, usageDict(from: response.usage))
                }
                let response = try await session.respond(
                    to: prompt,
                    schema: schema,
                    includeSchemaInPrompt: true,
                    options: options
                )
                let output = try jsonObject(fromGeneratedContent: response.content)
                if #available(macOS 27.0, *) {
                    return (output, usageDict(from: response.usage))
                }
                return (output, estimatedUsageDict(prompt: prompt, outputText: textForTokenEstimate(output)))
            } catch {
                throw mapNativeGenerationError(error, params: params)
            }
        }
        #endif

        throw JsonRpcError.modelUnavailable(
            "Apple Foundation Models require macOS 26 or newer.",
            data: ["code": "UNSUPPORTED_PLATFORM"]
        )
    }

    private func promptText(params: [String: Any]) -> String {
        (JSON.array(params, key: "input") ?? [])
            .compactMap { item in item["text"] as? String }
            .joined(separator: "\n")
    }

    private func hasImageParts(params: [String: Any]) -> Bool {
        (JSON.array(params, key: "input") ?? [])
            .contains { JSON.string($0, key: "type") == "image" }
    }

    /// TCK-0279 / FND-0216: image parts + unbound Attachment init must not
    /// degrade to silent text. The weak-imported symbol is a null pointer on
    /// SDK↔OS skew; calling it SIGSEGVs the daemon. Fail closed with the typed
    /// multimodal contract instead.
    private func rejectUnavailableAttachmentIfNeeded(params: [String: Any]) throws {
        guard hasImageParts(params: params) else { return }
        guard !AttachmentRuntimeAvailability.isAvailable else { return }
        throw JsonRpcError.unsupported(
            "Native multimodal Attachment binding is unavailable on this OS (FoundationModels SDK↔runtime symbol skew).",
            data: [
                "code": "MULTIMODAL_INPUT_UNAVAILABLE",
                "reasonCode": AttachmentRuntimeAvailability.unavailableReasonCode
            ]
        )
    }

    /// The native (`apple.system` / AFM) generation path a request must take.
    ///
    /// TCK-0224 / FND-0129 — `respond` and `stream` used to derive this locally,
    /// with the two checks in opposite order: `respond` looked at image parts
    /// first (dropping the schema), `stream` looked at `json_schema` first
    /// (dropping the images). Both silently discarded half the request. The
    /// route is now decided ONCE, by `nativeRoute(params:)`, so the two entry
    /// points cannot disagree — the divergence is inexpressible, not merely
    /// unlikely.
    ///
    /// `internal` (not `private`) on purpose: the pure decision function is what
    /// `FoundationModelsCoreDispatchTests` exercises via `@testable`.
    enum NativeRoute: Equatable {
        case text
        case structured
        case multimodal
        case multimodalStructured
    }

    /// Resolves the native route for `params` on this platform.
    func nativeRoute(params: [String: Any]) -> NativeRoute {
        nativeRoute(params: params, multimodalSupported: multimodalInputSupported())
    }

    /// The decision table — the single source of truth for native dispatch.
    ///
    /// | images | json_schema | multimodalSupported | route                |
    /// |--------|-------------|---------------------|----------------------|
    /// | yes    | yes         | yes                 | multimodalStructured |
    /// | yes    | yes         | no                  | structured           |
    /// | yes    | no          | yes                 | multimodal           |
    /// | yes    | no          | no                  | text                 |
    /// | no     | yes         | -                   | structured           |
    /// | no     | no          | -                   | text                 |
    ///
    /// The two `multimodalSupported: no` rows keep the pre-existing degrade: the
    /// TS provider gate already rejects image parts against a daemon reporting
    /// `multimodalInput: false`, so images only reach here from an older client
    /// or a hand-written RPC. They are dropped, but the response format the
    /// caller asked for is still honoured — which is why the degrade routes to
    /// `.structured` rather than `.text` when a schema is present.
    ///
    /// `multimodalSupported` is a parameter rather than a direct call to
    /// `multimodalInputSupported()` so every row above is reachable from a unit
    /// test on any host OS.
    func nativeRoute(params: [String: Any], multimodalSupported: Bool) -> NativeRoute {
        let wantsStructured = JSON.string(JSON.object(params, key: "responseFormat") ?? [:], key: "type") == "json_schema"
        let wantsMultimodal = hasImageParts(params: params) && multimodalSupported

        switch (wantsMultimodal, wantsStructured) {
        case (true, true):
            return .multimodalStructured
        case (true, false):
            return .multimodal
        case (false, true):
            return .structured
        case (false, false):
            return .text
        }
    }

    /// Returns the generated text plus its usage payload (FND-0157/FND-0162, TCK-0220): native
    /// `response.usage` when reached on macOS 27+, the word-count fallback (`estimated:true`)
    /// otherwise.
    private func generateText(
        prompt: String,
        params: [String: Any],
        toolBridge: Any?
    ) async throws -> (text: String, usage: [String: Any]) {
        if !CoreAIModelRegistry.isCoreAIModelId(JSON.string(params, key: "model")) {
            let status = systemModelStatus()
            guard status.available else {
                throw JsonRpcError.modelUnavailable(
                    "Apple Foundation Models are unavailable.",
                    data: [
                        "code": "APPLE_MODEL_UNAVAILABLE",
                        "reason": status.reason ?? "unknown",
                        "reasonCode": status.reasonCode ?? "unknown"
                    ]
                )
            }
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let session = try sessionFor(params: params, toolBridge: toolBridge)
            let options = try generationOptions(params: params)
            do {
                if let contextParams = try contextOptionsParams(params: params) {
                    guard #available(macOS 27.0, *) else {
                        throw contextOptionsUnavailableError()
                    }
                    let response = try await session.respond(
                        to: prompt,
                        options: options,
                        contextOptions: nativeContextOptions(contextParams)
                    )
                    return (response.content, usageDict(from: response.usage))
                }
                let response = try await session.respond(to: prompt, options: options)
                if #available(macOS 27.0, *) {
                    return (response.content, usageDict(from: response.usage))
                }
                return (response.content, estimatedUsageDict(prompt: prompt, outputText: response.content))
            } catch {
                throw mapNativeGenerationError(error, params: params)
            }
        }
        #endif

        throw JsonRpcError.modelUnavailable(
            "Apple Foundation Models require macOS 26 or newer.",
            data: ["code": "UNSUPPORTED_PLATFORM"]
        )
    }

    /// MLX guided-decoding respond path (TCK-0110d): validate the schema subset, generate JSON text
    /// via `MLXInferenceBackend.generateStructuredText`, and return a parsed JSON object.
    @available(macOS 27.0, *)
    private func generateStructuredOutputMLXDirect(
        prompt: String,
        params: [String: Any],
        modelId: String
    ) async throws -> Any {
        #if canImport(FoundationModels)
        if #available(macOS 27.0, *) {
            guard let registered = CoreAIModelRegistry.model(id: modelId) else {
                throw CoreAIModelRegistry.requestError(for: modelId)
            }
            let responseFormat = JSON.object(params, key: "responseFormat") ?? [:]
            let schema = try mlxGuidedSchema(from: responseFormat)
            let options = try generationOptions(params: params)
            let backend = (mlxBackendOverride as? any InferenceBackend) ?? MLXInferenceBackend()
            let text = try await backend.generateStructuredText(
                prompt: prompt,
                options: options,
                schema: schema,
                modelId: modelId,
                registryPath: registered.path
            )
            return try jsonObject(fromStructuredText: text)
        }
        #endif

        throw JsonRpcError.modelUnavailable(
            "MLX models require macOS 27 with FoundationModels.",
            data: [
                "code": "INFERENCE_BACKEND_UNAVAILABLE",
                "model": modelId,
                "reasonCode": "inference_backend_unavailable"
            ]
        )
    }

    /// MLX guided-decoding stream path (TCK-0110d): emits `structured_delta` snapshots whenever the
    /// accumulated JSON text parses to a new object, then terminal `result` + `done`.
    ///
    /// TCK-0257 / FND-0239 — `AccumulatedJSONEmitTracker` skips `JSONSerialization` on obvious
    /// partials and compares a single canonical `Data` (not double sortedKeys serialize) so the
    /// per-token path is no longer O(n²) parse+equality on the full buffer every delta.
    @available(macOS 27.0, *)
    private func streamStructuredOutputMLXDirect(
        params: [String: Any],
        prompt: String,
        modelId: String,
        traceId: String,
        emit: @escaping ([String: Any]) async throws -> Void
    ) async throws {
        #if canImport(FoundationModels)
        if #available(macOS 27.0, *) {
            guard let registered = CoreAIModelRegistry.model(id: modelId) else {
                throw CoreAIModelRegistry.requestError(for: modelId)
            }
            let responseFormat = JSON.object(params, key: "responseFormat") ?? [:]
            let schema = try mlxGuidedSchema(from: responseFormat)
            let options = try generationOptions(params: params)
            let backend = (mlxBackendOverride as? any InferenceBackend) ?? MLXInferenceBackend()
            var accumulated = ""
            var tracker = StreamingDelta.AccumulatedJSONEmitTracker()
            let result = try await backend.generateStructuredTextStream(
                prompt: prompt,
                options: options,
                schema: schema,
                modelId: modelId,
                registryPath: registered.path,
                onDelta: { delta in
                    try Task.checkCancellation()
                    guard !delta.isEmpty else { return }
                    accumulated += delta
                    guard let object = tracker.consider(
                        accumulatedText: accumulated,
                        parse: { text in try? self.jsonObject(fromStructuredText: text) }
                    ) else {
                        return
                    }
                    try await emit(["type": "structured_delta", "object": object])
                }
            )
            try Task.checkCancellation()
            if let lateObject = try tracker.considerFinal(
                text: result.text,
                parse: { text in try self.jsonObject(fromStructuredText: text) }
            ) {
                try await emit(["type": "structured_delta", "object": lateObject])
            }
            let finalObject: Any
            if let last = tracker.lastObject {
                finalObject = last
            } else {
                finalObject = try jsonObject(fromStructuredText: result.text)
            }
            try await emit([
                "type": "result",
                "response": [
                    "output": finalObject,
                    "model": modelId,
                    // MLX-direct bypasses `LanguageModelSession` entirely (never sees native
                    // usage, regardless of macOS version) — always the word-count estimate
                    // (FND-0157, TCK-0220).
                    "usage": [
                        "inputTokens": estimateTokens(prompt),
                        "outputTokens": estimateTokens(textForTokenEstimate(finalObject)),
                        "estimated": true
                    ],
                    "traceId": traceId
                ]
            ])
            try await emit(["type": "done"])
            return
        }
        #endif

        throw JsonRpcError.modelUnavailable(
            "MLX models require macOS 27 with FoundationModels.",
            data: [
                "code": "INFERENCE_BACKEND_UNAVAILABLE",
                "model": modelId,
                "reasonCode": "inference_backend_unavailable"
            ]
        )
    }

    @available(macOS 27.0, *)
    private func mlxGuidedSchema(from responseFormat: [String: Any]) throws -> [String: Any] {
        guard let schemaObject = responseFormat["schema"] as? [String: Any] else {
            throw JsonRpcError.invalidRequest("responseFormat.schema must be a JSON Schema object.")
        }
        do {
            _ = try JSONSchemaSupport.compile(rootSchema: schemaObject)
        } catch let error as JSONSchemaCompileError {
            throw mapJSONSchemaCompileError(error)
        } catch {
            throw JsonRpcError.invalidRequest("responseFormat.schema is invalid: \(error)")
        }
        return schemaObject
    }

    @available(macOS 27.0, *)
    private func mapJSONSchemaCompileError(_ error: JSONSchemaCompileError) -> JsonRpcError {
        switch error {
        case .unsupportedKeyword(let keyword, let path):
            return JsonRpcError.unsupported(
                "JSON Schema keyword '\(keyword)' at \(path) is not supported by MLX guided generation.",
                data: ["code": "UNSUPPORTED_SCHEMA_TYPE", "keyword": keyword, "path": path]
            )
        case .unsupportedType(let type, let path):
            return JsonRpcError.unsupported(
                "JSON Schema type '\(type)' at \(path) is not supported by MLX guided generation.",
                data: ["code": "UNSUPPORTED_SCHEMA_TYPE", "keyword": "type", "path": path]
            )
        case .invalidSchema(let message):
            return JsonRpcError.invalidRequest(message)
        }
    }

    private func jsonObject(fromStructuredText text: String) throws -> Any {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw JsonRpcError.modelUnavailable(
                "Structured generation returned empty output.",
                data: ["code": "STRUCTURED_OUTPUT_EMPTY", "reasonCode": "structured_output_empty"]
            )
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw JsonRpcError.modelUnavailable(
                "Structured generation returned non-UTF8 output.",
                data: ["code": "STRUCTURED_OUTPUT_INVALID", "reasonCode": "structured_output_invalid"]
            )
        }
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw JsonRpcError.modelUnavailable(
                "Structured generation returned invalid JSON.",
                data: [
                    "code": "STRUCTURED_OUTPUT_INVALID",
                    "reasonCode": "structured_output_invalid",
                    "detail": error.localizedDescription
                ]
            )
        }
    }

    /// MLX-direct-path (ADR-0006 / DES-0051): resolve the registered model and call the
    /// `MLXInferenceBackend` directly, returning the generated text WITHOUT a
    /// `LanguageModelSession`. This is what unblocks real `apple.mlx:*` text generation on the
    /// SDK 27 beta (the executor/channel path stays gated). Fail-closed: unregistered id →
    /// typed `MODEL_NOT_FOUND`; pre-macOS-27 → typed `INFERENCE_BACKEND_UNAVAILABLE`.
    private func generateTextMLXDirect(prompt: String, params: [String: Any], modelId: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 27.0, *) {
            guard let registered = CoreAIModelRegistry.model(id: modelId) else {
                throw CoreAIModelRegistry.requestError(for: modelId)
            }
            let options = try generationOptions(params: params)
            let backend = (mlxBackendOverride as? any InferenceBackend) ?? MLXInferenceBackend()
            return try await backend.generateText(
                prompt: prompt,
                options: options,
                modelId: modelId,
                registryPath: registered.path
            )
        }
        #endif

        throw JsonRpcError.modelUnavailable(
            "MLX models require macOS 27 with FoundationModels.",
            data: [
                "code": "INFERENCE_BACKEND_UNAVAILABLE",
                "model": modelId,
                "reasonCode": "inference_backend_unavailable"
            ]
        )
    }

    /// MLX vision-direct-path (TCK-0109): resolve the registered VLM, extract image parts, and call
    /// `MLXInferenceBackend.generateVisionText` (VLMModelFactory). Only reached for `apple.mlx:*`
    /// models whose registry backend is `mlx-vlm`.
    private func generateVisionTextMLXDirect(prompt: String, params: [String: Any], modelId: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 27.0, *) {
            guard let registered = CoreAIModelRegistry.model(id: modelId) else {
                throw CoreAIModelRegistry.requestError(for: modelId)
            }
            let options = try generationOptions(params: params)
            let parts = try parseMultimodalInput(from: params)
            var imageData: [Data] = []
            for part in parts {
                switch part {
                case .image(let data, _, _):
                    imageData.append(data)
                case .imageURL(let url, _, _):
                    // Fail-closed: a declared image that can't be read is an error, not a silent drop.
                    do {
                        imageData.append(try Data(contentsOf: url))
                    } catch {
                        throw JsonRpcError.modelUnavailable(
                            "Could not read the image for model \"\(modelId)\".",
                            data: [
                                "code": "MULTIMODAL_INPUT_UNAVAILABLE",
                                "model": modelId,
                                "reasonCode": "mlx_image_url_unreadable"
                            ]
                        )
                    }
                case .text:
                    break
                }
            }
            let backend = (mlxBackendOverride as? any InferenceBackend) ?? MLXInferenceBackend()
            return try await backend.generateVisionText(
                prompt: prompt,
                imageData: imageData,
                options: options,
                modelId: modelId,
                registryPath: registered.path
            )
        }
        #endif

        throw JsonRpcError.modelUnavailable(
            "MLX vision models require macOS 27 with FoundationModels.",
            data: [
                "code": "INFERENCE_BACKEND_UNAVAILABLE",
                "model": modelId,
                "reasonCode": "inference_backend_unavailable"
            ]
        )
    }

    /// MLX vision streaming (TCK-0111): like `generateVisionTextMLXDirect`, but streams real per-token
    /// `delta` events from the VLM decode loop, then a terminal `result` + `done`.
    private func streamVisionMLXDirect(
        params: [String: Any],
        prompt: String,
        modelId: String,
        traceId: String,
        emit: ([String: Any]) async throws -> Void
    ) async throws {
        #if canImport(FoundationModels)
        if #available(macOS 27.0, *) {
            guard let registered = CoreAIModelRegistry.model(id: modelId) else {
                throw CoreAIModelRegistry.requestError(for: modelId)
            }
            let options = try generationOptions(params: params)
            let parts = try parseMultimodalInput(from: params)
            var imageData: [Data] = []
            for part in parts {
                switch part {
                case .image(let data, _, _):
                    imageData.append(data)
                case .imageURL(let url, _, _):
                    do {
                        imageData.append(try Data(contentsOf: url))
                    } catch {
                        throw JsonRpcError.modelUnavailable(
                            "Could not read the image for model \"\(modelId)\".",
                            data: [
                                "code": "MULTIMODAL_INPUT_UNAVAILABLE",
                                "model": modelId,
                                "reasonCode": "mlx_image_url_unreadable"
                            ]
                        )
                    }
                case .text:
                    break
                }
            }
            let backend = (mlxBackendOverride as? any InferenceBackend) ?? MLXInferenceBackend()
            let result = try await backend.generateVisionTextStream(
                prompt: prompt,
                imageData: imageData,
                options: options,
                modelId: modelId,
                registryPath: registered.path,
                onDelta: { delta in
                    if !delta.isEmpty {
                        try await emit(["type": "delta", "text": delta])
                    }
                }
            )
            try await emit([
                "type": "result",
                "response": [
                    "output": result.text,
                    "model": modelId,
                    // MLX-direct bypasses `LanguageModelSession` (FND-0157, TCK-0220).
                    "usage": [
                        "inputTokens": estimateTokens(prompt),
                        "outputTokens": estimateTokens(result.text),
                        "estimated": true
                    ],
                    "traceId": traceId
                ]
            ])
            try await emit(["type": "done"])
            return
        }
        #endif

        throw JsonRpcError.modelUnavailable(
            "MLX vision models require macOS 27 with FoundationModels.",
            data: [
                "code": "INFERENCE_BACKEND_UNAVAILABLE",
                "model": modelId,
                "reasonCode": "inference_backend_unavailable"
            ]
        )
    }

    /// MLX-direct streaming (TCK-0106): stream the mlx-swift-lm decode loop as `delta` events, then
    /// a terminal `result` + `done`, bypassing `LanguageModelSession`. Structured output and
    /// multimodal are out of scope for the MLX path -> typed errors (no false success), matching the
    /// non-streaming `respond` branch.
    private func streamMLXDirect(
        params: [String: Any],
        prompt: String,
        modelId: String,
        traceId: String,
        emit: @escaping ([String: Any]) async throws -> Void
    ) async throws {
        // Check json_schema FIRST (same order as `respond`) so a {image + json_schema} request gets
        // the structured-output rejection, not a misleading "use respond()" — respond would reject it too.
        if JSON.string(JSON.object(params, key: "responseFormat") ?? [:], key: "type") == "json_schema" {
            if hasImageParts(params: params) {
                throw JsonRpcError.modelUnavailable(
                    "Structured output (json_schema) with multimodal input is not supported for MLX models (\(modelId)).",
                    data: [
                        "code": "STRUCTURED_OUTPUT_UNAVAILABLE",
                        "model": modelId,
                        "reasonCode": "mlx_structured_multimodal_unsupported"
                    ]
                )
            }
            try await streamStructuredOutputMLXDirect(
                params: params,
                prompt: prompt,
                modelId: modelId,
                traceId: traceId,
                emit: emit
            )
            return
        }
        if hasImageParts(params: params) {
            // VLM (TCK-0111): a vision model (backend "mlx-vlm") streams real deltas from the decode
            // loop, like the text path; a text-only model rejects images with a typed error.
            if CoreAIModelRegistry.model(id: modelId)?.backend == "mlx-vlm" {
                try await streamVisionMLXDirect(params: params, prompt: prompt, modelId: modelId, traceId: traceId, emit: emit)
                return
            }
            throw JsonRpcError.modelUnavailable(
                "Multimodal input is not supported for MLX model \(modelId) (text-only).",
                data: [
                    "code": "MULTIMODAL_INPUT_UNAVAILABLE",
                    "model": modelId,
                    "reasonCode": "mlx_multimodal_unsupported"
                ]
            )
        }

        #if canImport(FoundationModels)
        if #available(macOS 27.0, *) {
            guard let registered = CoreAIModelRegistry.model(id: modelId) else {
                throw CoreAIModelRegistry.requestError(for: modelId)
            }
            let options = try generationOptions(params: params)
            let backend = (mlxBackendOverride as? any InferenceBackend) ?? MLXInferenceBackend()
            let result = try await backend.generateTextStream(
                prompt: prompt,
                options: options,
                modelId: modelId,
                registryPath: registered.path,
                onDelta: { delta, _ in
                    // MLX never sets isSnapshotReplace (TCK-0121 scope: isolated to CoreAI).
                    if !delta.isEmpty {
                        try await emit(["type": "delta", "text": delta])
                    }
                }
            )
            try await emit([
                "type": "result",
                "response": [
                    "output": result.text,
                    "model": modelId,
                    // MLX-direct bypasses `LanguageModelSession` (FND-0157, TCK-0220).
                    "usage": [
                        "inputTokens": estimateTokens(prompt),
                        "outputTokens": estimateTokens(result.text),
                        "estimated": true
                    ],
                    "traceId": traceId
                ]
            ])
            try await emit(["type": "done"])
            return
        }
        #endif

        throw JsonRpcError.modelUnavailable(
            "MLX models require macOS 27 with FoundationModels.",
            data: [
                "code": "INFERENCE_BACKEND_UNAVAILABLE",
                "model": modelId,
                "reasonCode": "inference_backend_unavailable"
            ]
        )
    }

    /// CoreAI-direct-path (ADR-0007): resolve the registered model and call `CoreAIInferenceBackend`
    /// directly, returning text WITHOUT the custom executor / sealed channel. Fail-closed.
    private func generateTextCoreAIDirect(prompt: String, params: [String: Any], modelId: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 27.0, *) {
            guard let registered = CoreAIModelRegistry.model(id: modelId) else {
                throw CoreAIModelRegistry.requestError(for: modelId)
            }
            let options = try generationOptions(params: params)
            let backend = (coreaiBackendOverride as? any InferenceBackend) ?? CoreAIInferenceBackend()
            return try await backend.generateText(
                prompt: prompt,
                options: options,
                modelId: modelId,
                registryPath: registered.path
            )
        }
        #endif

        throw JsonRpcError.modelUnavailable(
            "CoreAI models require macOS 27 with FoundationModels.",
            data: [
                "code": "INFERENCE_BACKEND_UNAVAILABLE",
                "model": modelId,
                "reasonCode": "inference_backend_unavailable"
            ]
        )
    }

    /// CoreAI-direct streaming (ADR-0007): stream `LanguageModelSession.streamResponse` of the
    /// CoreAILanguageModels model as `delta` events, then `result` + `done`, bypassing the channel.
    /// Structured output + multimodal are out of scope → typed errors.
    private func streamCoreAIDirect(
        params: [String: Any],
        prompt: String,
        modelId: String,
        traceId: String,
        emit: ([String: Any]) async throws -> Void
    ) async throws {
        if hasImageParts(params: params) {
            throw JsonRpcError.modelUnavailable(
                "Multimodal input is not supported for CoreAI models (\(modelId)).",
                data: [
                    "code": "MULTIMODAL_INPUT_UNAVAILABLE",
                    "model": modelId,
                    "reasonCode": "coreai_multimodal_unsupported"
                ]
            )
        }
        if JSON.string(JSON.object(params, key: "responseFormat") ?? [:], key: "type") == "json_schema" {
            throw JsonRpcError.modelUnavailable(
                "Structured output (json_schema) is not supported for CoreAI models (\(modelId)). Use plain text generation.",
                data: [
                    "code": "STRUCTURED_OUTPUT_UNAVAILABLE",
                    "model": modelId,
                    "reasonCode": "coreai_structured_unsupported"
                ]
            )
        }

        #if canImport(FoundationModels)
        if #available(macOS 27.0, *) {
            guard let registered = CoreAIModelRegistry.model(id: modelId) else {
                throw CoreAIModelRegistry.requestError(for: modelId)
            }
            let options = try generationOptions(params: params)
            let backend = (coreaiBackendOverride as? any InferenceBackend) ?? CoreAIInferenceBackend()
            let result = try await backend.generateTextStream(
                prompt: prompt,
                options: options,
                modelId: modelId,
                registryPath: registered.path,
                onDelta: { delta, isSnapshotReplace in
                    if !delta.isEmpty {
                        // TCK-0121 / FND-0074: isSnapshotReplace marks the rare non-prefix
                        // snapshot case. The JS-facing event carries it so the consumer REPLACES
                        // its accumulated buffer instead of appending `text` (appending here
                        // would duplicate/corrupt the rendered text).
                        try await emit(["type": "delta", "text": delta, "isSnapshotReplace": isSnapshotReplace])
                    }
                }
            )
            try await emit([
                "type": "result",
                "response": [
                    "output": result.text,
                    "model": modelId,
                    // CoreAI-direct bypasses `LanguageModelSession` too (FND-0157, TCK-0220).
                    "usage": [
                        "inputTokens": estimateTokens(prompt),
                        "outputTokens": estimateTokens(result.text),
                        "estimated": true
                    ],
                    "traceId": traceId
                ]
            ])
            try await emit(["type": "done"])
            return
        }
        #endif

        throw JsonRpcError.modelUnavailable(
            "CoreAI models require macOS 27 with FoundationModels.",
            data: [
                "code": "INFERENCE_BACKEND_UNAVAILABLE",
                "model": modelId,
                "reasonCode": "inference_backend_unavailable"
            ]
        )
    }

    /// Native multimodal text generation using `Attachment<ImageAttachmentContent>` (macOS 27+).
    ///
    /// Parses the request into `MultimodalInputPart` values (text and image),
    /// then assembles a `Prompt` via `buildNativePrompt(from:)`. Each image part
    /// is decoded from its already-validated `Data` to `CGImage` via ImageIO and
    /// wrapped in an `Attachment<ImageAttachmentContent>` — the SDK type that
    /// implements `PromptRepresentable` for image content. The assembled `Prompt`
    /// is passed to `session.respond(to:options:)`.
    ///
    /// On platforms where macOS 27+ is unavailable or the `FoundationModels`
    /// module is absent at compile time, the method degrades to the typed
    /// `MULTIMODAL_INPUT_UNAVAILABLE` error — never to a crash.
    ///
    /// Returns the generated text plus its usage payload. Always macOS 27+ here, so
    /// `response.usage` (FND-0157/FND-0162, TCK-0220) is unconditionally native — this path never
    /// falls back to the word-count estimator.
    private func generateMultimodalText(
        params: [String: Any],
        toolBridge: Any?
    ) async throws -> (text: String, usage: [String: Any]) {
        let parts = try parseMultimodalInput(from: params)

        #if canImport(FoundationModels)
        if #available(macOS 27.0, *) {
            let status = systemModelStatus()
            guard status.available else {
                throw JsonRpcError.modelUnavailable(
                    "Apple Foundation Models are unavailable.",
                    data: [
                        "code": "APPLE_MODEL_UNAVAILABLE",
                        "reason": status.reason ?? "unknown",
                        "reasonCode": status.reasonCode ?? "unknown"
                    ]
                )
            }

            let nativePrompt = try buildNativePrompt(from: parts)
            let session = try sessionFor(params: params, toolBridge: toolBridge)
            let options = try generationOptions(params: params)
            let contextParams = try contextOptionsParams(params: params)
            do {
                let response: LanguageModelSession.Response<String>
                if let contextParams {
                    response = try await session.respond(
                        to: nativePrompt,
                        options: options,
                        contextOptions: nativeContextOptions(contextParams)
                    )
                } else {
                    response = try await session.respond(to: nativePrompt, options: options)
                }
                return (response.content, usageDict(from: response.usage))
            } catch {
                throw mapNativeGenerationError(error, params: params)
            }
        }
        #endif

        throw JsonRpcError.unsupported(
            "Native multimodal binding requires macOS 27+.",
            data: ["code": "MULTIMODAL_INPUT_UNAVAILABLE"]
        )
    }

    /// Native guided generation over a multimodal prompt (`NativeRoute.multimodalStructured`).
    ///
    /// TCK-0224 / FND-0129 — `image` parts and a `json_schema` response format
    /// are NOT mutually exclusive on the Apple-native path: the SDK exposes
    /// `respond(to: Prompt, schema:, includeSchemaInPrompt:, options:)`, and an
    /// `Attachment<ImageAttachmentContent>` is `PromptRepresentable`, so the very
    /// `Prompt` that `generateMultimodalText` already builds can carry a schema.
    /// Before this ticket the schema was silently discarded here.
    ///
    /// Same shape as `generateStructuredOutput`, with `buildNativePrompt(from:)`
    /// in place of the plain text prompt. Availability is macOS 27 — the same
    /// gate the rest of the multimodal path already requires (`Attachment`).
    ///
    /// Returns the parsed JSON object plus its usage payload (FND-0157/FND-0162, TCK-0220).
    /// Always macOS 27+ here (same gate as `generateMultimodalText`), so `response.usage` is
    /// unconditionally native — mirrors what `streamMultimodalStructuredOutput` already gets
    /// for free via `consumeStructuredStream`.
    private func generateMultimodalStructuredOutput(
        params: [String: Any],
        toolBridge: Any?
    ) async throws -> (output: Any, usage: [String: Any]) {
        let parts = try parseMultimodalInput(from: params)

        #if canImport(FoundationModels)
        if #available(macOS 27.0, *) {
            let status = systemModelStatus()
            guard status.available else {
                throw JsonRpcError.modelUnavailable(
                    "Apple Foundation Models are unavailable.",
                    data: [
                        "code": "APPLE_MODEL_UNAVAILABLE",
                        "reason": status.reason ?? "unknown",
                        "reasonCode": status.reasonCode ?? "unknown"
                    ]
                )
            }

            let responseFormat = JSON.object(params, key: "responseFormat") ?? [:]
            // TCK-0208: schema-compilation errors go through the contract mapper,
            // exactly as on the text-prompt structured path.
            let schema: GenerationSchema
            do {
                schema = try generationSchema(from: responseFormat["schema"])
            } catch {
                throw mapNativeGenerationError(error, params: params)
            }

            let nativePrompt = try buildNativePrompt(from: parts)
            let session = try sessionFor(params: params, toolBridge: toolBridge)
            let options = try generationOptions(params: params)
            let contextParams = try contextOptionsParams(params: params)
            do {
                let response: LanguageModelSession.Response<GeneratedContent>
                if let contextParams {
                    response = try await session.respond(
                        to: nativePrompt,
                        schema: schema,
                        options: options,
                        contextOptions: nativeContextOptions(contextParams, includeSchemaInPromptDefault: true)
                    )
                } else {
                    response = try await session.respond(
                        to: nativePrompt,
                        schema: schema,
                        includeSchemaInPrompt: true,
                        options: options
                    )
                }
                let output = try jsonObject(fromGeneratedContent: response.content)
                return (output, usageDict(from: response.usage))
            } catch {
                throw mapNativeGenerationError(error, params: params)
            }
        }
        #endif

        throw JsonRpcError.unsupported(
            "Native multimodal structured output requires macOS 27+.",
            data: ["code": "MULTIMODAL_INPUT_UNAVAILABLE"]
        )
    }

    /// Streaming counterpart of `generateMultimodalText` using `Attachment<ImageAttachmentContent>` (macOS 27+).
    ///
    /// Same prompt-building logic as `generateMultimodalText`; uses
    /// `session.streamResponse(to:options:)` and emits delta/result/done events
    /// in the same format as the text-only streaming path.
    private func streamMultimodalText(
        params: [String: Any],
        toolBridge: Any?,
        traceId: String,
        emit: ([String: Any]) async throws -> Void
    ) async throws {
        let parts = try parseMultimodalInput(from: params)

        #if canImport(FoundationModels)
        if #available(macOS 27.0, *) {
            let status = systemModelStatus()
            guard status.available else {
                throw JsonRpcError.modelUnavailable(
                    "Apple Foundation Models are unavailable.",
                    data: [
                        "code": "APPLE_MODEL_UNAVAILABLE",
                        "reason": status.reason ?? "unknown",
                        "reasonCode": status.reasonCode ?? "unknown"
                    ]
                )
            }

            let nativePrompt = try buildNativePrompt(from: parts)
            let session = try sessionFor(params: params, toolBridge: toolBridge)
            let options = try generationOptions(params: params)
            let contextParams = try contextOptionsParams(params: params)
            var accumulated = ""
            // Always macOS 27+ in this function, so `usageDict(from:)` is unconditionally native
            // here (FND-0157/FND-0162, TCK-0220) — no word-count fallback branch is reachable.
            var lastUsage: [String: Any]?
            do {
                let stream: LanguageModelSession.ResponseStream<String>
                if let contextParams {
                    stream = session.streamResponse(
                        to: nativePrompt,
                        options: options,
                        contextOptions: nativeContextOptions(contextParams)
                    )
                } else {
                    stream = session.streamResponse(to: nativePrompt, options: options)
                }
                for try await snapshot in stream {
                    try Task.checkCancellation()

                    lastUsage = usageDict(from: snapshot.usage)

                    let next = snapshot.content
                    let delta = textDelta(previous: accumulated, next: next)
                    accumulated = next
                    if !delta.isEmpty {
                        try await emit(["type": "delta", "text": delta])
                    }
                }

                if accumulated.isEmpty {
                    let response: LanguageModelSession.Response<String>
                    if let contextParams {
                        response = try await session.respond(
                            to: nativePrompt,
                            options: options,
                            contextOptions: nativeContextOptions(contextParams)
                        )
                    } else {
                        response = try await session.respond(to: nativePrompt, options: options)
                    }
                    accumulated = response.content
                    lastUsage = usageDict(from: response.usage)
                    if !accumulated.isEmpty {
                        try await emit(["type": "delta", "text": accumulated])
                    }
                }

                try Task.checkCancellation()
                let prompt = textOnlyPrompt(from: parts)
                try await emit([
                    "type": "result",
                    "response": [
                        "output": accumulated,
                        "model": JSON.string(params, key: "model") ?? "apple.system",
                        "usage": lastUsage ?? estimatedUsageDict(prompt: prompt, outputText: accumulated),
                        "traceId": traceId
                    ]
                ])
                try await emit(["type": "done"])
            } catch {
                throw mapNativeGenerationError(error, params: params)
            }
            return
        }
        #endif

        throw JsonRpcError.unsupported(
            "Native multimodal streaming requires macOS 27+.",
            data: ["code": "MULTIMODAL_INPUT_UNAVAILABLE"]
        )
    }

    /// Streaming counterpart of `generateMultimodalStructuredOutput` (`NativeRoute.multimodalStructured`).
    ///
    /// TCK-0224 / FND-0129 — uses `streamResponse(to: Prompt, schema:, ...)` so a
    /// request carrying both `image` parts and a `json_schema` response format
    /// keeps BOTH, and shares `consumeStructuredStream` with the text-prompt
    /// variant so the emitted events (`structured_delta` → `result` → `done`)
    /// are identical by construction.
    private func streamMultimodalStructuredOutput(
        params: [String: Any],
        toolBridge: Any?,
        traceId: String,
        emit: ([String: Any]) async throws -> Void
    ) async throws {
        let parts = try parseMultimodalInput(from: params)

        #if canImport(FoundationModels)
        if #available(macOS 27.0, *) {
            let status = systemModelStatus()
            guard status.available else {
                throw JsonRpcError.modelUnavailable(
                    "Apple Foundation Models are unavailable.",
                    data: [
                        "code": "APPLE_MODEL_UNAVAILABLE",
                        "reason": status.reason ?? "unknown",
                        "reasonCode": status.reasonCode ?? "unknown"
                    ]
                )
            }

            let responseFormat = JSON.object(params, key: "responseFormat") ?? [:]
            let schema: GenerationSchema
            do {
                schema = try generationSchema(from: responseFormat["schema"])
            } catch {
                throw mapNativeGenerationError(error, params: params)
            }

            let nativePrompt = try buildNativePrompt(from: parts)
            let session = try sessionFor(params: params, toolBridge: toolBridge)
            let options = try generationOptions(params: params)
            let contextParams = try contextOptionsParams(params: params)

            let stream: LanguageModelSession.ResponseStream<GeneratedContent>
            if let contextParams {
                stream = session.streamResponse(
                    to: nativePrompt,
                    schema: schema,
                    options: options,
                    contextOptions: nativeContextOptions(contextParams, includeSchemaInPromptDefault: true)
                )
            } else {
                stream = session.streamResponse(
                    to: nativePrompt,
                    schema: schema,
                    includeSchemaInPrompt: true,
                    options: options
                )
            }

            try await consumeStructuredStream(
                stream: stream,
                params: params,
                promptForTokens: textOnlyPrompt(from: parts),
                traceId: traceId,
                emit: emit
            )
            return
        }
        #endif

        throw JsonRpcError.unsupported(
            "Native multimodal structured streaming requires macOS 27+.",
            data: ["code": "MULTIMODAL_INPUT_UNAVAILABLE"]
        )
    }

    /// Builds a `Prompt` from validated multimodal input parts (macOS 27+).
    ///
    /// Accumulates text parts as a single joined string and image parts as
    /// `Attachment<ImageAttachmentContent>` values decoded via ImageIO. The
    /// resulting `[any PromptRepresentable]` list is folded into a single
    /// `Prompt` using `Prompt(_ content: some PromptRepresentable)` iteratively.
    ///
    /// If ImageIO cannot decode an image (e.g. an unsupported mimeType), the
    /// method throws `MULTIMODAL_INPUT_UNAVAILABLE` with a descriptive message
    /// rather than crashing the daemon.
    #if canImport(FoundationModels)
    /// TCK-0227 / FND-0147 — builds one of Apple's model-callable vision tools.
    ///
    /// Both take `Arguments = { image: ImageReference }`, i.e. the model names an
    /// attachment by LABEL and the tool resolves it from the transcript; it never
    /// receives pixels. That is the difference from `createOCRTool` in
    /// `systemTools.ts`, whose schema asks the model for `image.base64` — a blob
    /// no language model can emit, which makes ours operator-invoked in practice.
    ///
    /// Apple's defaults are `getText` / `readBarcodes` (measured, not assumed —
    /// `scripts/smoke/probe-agentic-vision.swift`); a caller may rename them, for
    /// instance to avoid colliding with a bridge tool of the same name.
    ///
    /// An unknown `native` value is a typed error rather than a skipped tool: a
    /// silently dropped tool yields a session that answers as though the caller
    /// never asked for it, which is far harder to diagnose than a rejection.
    @available(macOS 26.0, *)
    private func nativeVisionTool(kind: String, name: String?, description: String?) throws -> any Tool {
        guard #available(macOS 27.0, *) else {
            throw JsonRpcError.unsupported(
                "Apple's native vision tools require macOS 27 or newer.",
                data: ["code": "SYSTEM_TOOL_UNAVAILABLE", "native": kind, "reasonCode": "unsupported_platform"]
            )
        }

        switch kind {
        case "ocr":
            return OCRTool(name: name, description: description)
        case "barcode":
            return BarcodeReaderTool(name: name, description: description)
        default:
            throw JsonRpcError.invalidRequest(
                "Unknown native tool \"\(kind)\". Supported: \"ocr\", \"barcode\"."
            )
        }
    }

    /// TCK-0227 / FND-0147 — applies Apple's attachment label when the caller
    /// supplied one.
    ///
    /// Kept as a helper rather than inlined at both call sites because
    /// `label(_:)` is a builder that returns a NEW attachment: writing
    /// `attachment.label(x)` and discarding the result is a silent no-op, and
    /// having one place that returns the labelled copy removes that trap.
    @available(macOS 27.0, *)
    private func labelled(
        _ attachment: Attachment<ImageAttachmentContent>,
        _ label: String?
    ) -> Attachment<ImageAttachmentContent> {
        guard let label else { return attachment }
        return attachment.label(label)
    }

    @available(macOS 27.0, *)
    private func buildNativePrompt(from parts: [MultimodalInputPart]) throws -> Prompt {
        // TCK-0279 / FND-0216: never call the weak-imported Attachment init when
        // the OS did not bind it — that is a null jump (daemon SIGSEGV), not a
        // Swift throw. Probe first; emit the same MULTIMODAL_INPUT_UNAVAILABLE
        // contract the rest of the multimodal surface already uses.
        guard AttachmentRuntimeAvailability.isAvailable else {
            throw JsonRpcError.unsupported(
                "Native multimodal Attachment binding is unavailable on this OS (FoundationModels SDK↔runtime symbol skew).",
                data: [
                    "code": "MULTIMODAL_INPUT_UNAVAILABLE",
                    "reasonCode": AttachmentRuntimeAvailability.unavailableReasonCode
                ]
            )
        }

        // Collect PromptRepresentable components in input order.
        var components: [Prompt] = []
        for part in parts {
            switch part {
            case .text(let text):
                components.append(Prompt(text))
            case .image(let data, let mimeType, let label):
                guard
                    let source = CGImageSourceCreateWithData(data as CFData, nil),
                    let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
                else {
                    throw JsonRpcError.unsupported(
                        "Could not decode image data as CGImage (mimeType: \(mimeType)).",
                        data: ["code": "MULTIMODAL_INPUT_UNAVAILABLE", "mimeType": mimeType]
                    )
                }
                // Attachment<ImageAttachmentContent> implements PromptRepresentable
                // and is the SDK-endorsed path for inline CGImage prompts.
                //
                // TCK-0226 / FND-0150: forward the EXIF orientation as metadata so
                // the model sees the photo the right way up. `imageOrientation` is
                // read from the very source that produced `cgImage`, and yields nil
                // for untagged images — which is byte-identical to the previous
                // behaviour, since the parameter defaults to nil.
                // TCK-0227 / FND-0147: `.label(_:)` is what makes the image
                // addressable by the model — Apple's vision tools receive an
                // `ImageReference { attachmentLabel }`, never pixels. Unlabelled
                // images stay exactly as before.
                let imageAttachment = labelled(
                    Attachment<ImageAttachmentContent>(cgImage, orientation: imageOrientation(from: source)),
                    label
                )
                components.append(Prompt(imageAttachment))
            case .imageURL(let url, _, let label):
                // TCK-0043 / SPC-0037: native file URL route. Load via ImageIO
                // instead of Attachment(imageURL:) so the binary does not depend on
                // SDK-only Attachment.ImageContent.imageURL(orientation:) symbols
                // (TCK-0150 — mismatch between Xcode-beta SDK and installed OS framework).
                guard
                    let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                    let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
                else {
                    throw JsonRpcError.unsupported(
                        "Could not load image from file URL.",
                        data: ["code": "MULTIMODAL_INPUT_UNAVAILABLE", "imageURL": url.absoluteString]
                    )
                }
                // TCK-0226 / FND-0150: same orientation forwarding as the base64
                // branch. Loading through ImageIO is what makes the tag reachable
                // here at all — the avoided native imageURL init would have read it
                // for us, but carries the SDK-only symbol this binary must not need.
                let imageAttachment = labelled(
                    Attachment<ImageAttachmentContent>(cgImage, orientation: imageOrientation(from: source)),
                    label
                )
                components.append(Prompt(imageAttachment))
            }
        }
        // Fold into a single Prompt via Array<PromptRepresentable>.promptRepresentation.
        return components.promptRepresentation
    }
    #endif

    private func foundationModelsAPISupported() -> Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return true
        }
        #endif

        return false
    }

    /// FND-0200: `structuredOutput` used to equal `foundationModelsAPISupported()`
    /// everywhere — an OS-version-plus-`canImport` check, never a read of the
    /// model's actual guided-generation capability. On macOS 27+,
    /// `SystemLanguageModel` conforms to `LanguageModel` and exposes
    /// `capabilities` (SDK 27 swiftinterface L217-219), whose
    /// `Capability.guidedGeneration` (L1194) is the real, measured answer —
    /// the same movement TCK-0223 made for `apple.pcc`, applied here to the
    /// system model. Below macOS 27 that API does not exist, so the
    /// pre-existing OS-gate literal is kept as the fallback (unchanged
    /// behavior for macOS 26.x).
    private func structuredOutputSupported() -> Bool {
        #if canImport(FoundationModels)
        if #available(macOS 27.0, *) {
            return SystemLanguageModel.default.capabilities.contains(.guidedGeneration)
        }
        if #available(macOS 26.0, *) {
            return true
        }
        #endif

        return false
    }

    /// FND-0236 / TCK-0254: `multimodalInput` used to hard-code `true` on
    /// macOS 27+ (`#available` only) — the same class of unfalsifiable claim
    /// FND-0200 fixed for `structuredOutput`. On macOS 27+,
    /// `SystemLanguageModel.default.capabilities.contains(.vision)` is the
    /// measured answer (same pattern as `pccCapabilityDict` / TCK-0223). Below
    /// macOS 27 the native multimodal binding does not exist, so the result
    /// stays `false` (unchanged pre-27 behaviour).
    ///
    /// TCK-0279 / FND-0216: AND with `AttachmentRuntimeAvailability` — the
    /// weak-imported `Attachment` CGImage init is a null function pointer on
    /// SDK↔OS mangling skew (Rszrl vs Rszl). Reporting `supports.image: true`
    /// then crashing in `buildNativePrompt` is worse than an honest `false`.
    private func multimodalInputSupported() -> Bool {
        #if canImport(FoundationModels)
        if #available(macOS 27.0, *) {
            guard AttachmentRuntimeAvailability.isAvailable else {
                return false
            }
            return SystemLanguageModel.default.capabilities.contains(.vision)
        }
        #endif

        return false
    }

    private func tokenCountingAPISupported() -> Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.4, *) {
            return true
        }
        #endif

        return false
    }

    /// Platform-neutral, validated representation of the request-level
    /// `contextOptions` object (TCK-0205 / DES-0058). Parsed fail-fast on every
    /// platform; mapped to the native `ContextOptions` only on macOS 27+.
    struct ContextOptionsParams: Equatable {
        enum ReasoningLevel: Equatable {
            case light
            case moderate
            case deep
            case custom(String)
        }

        var includeSchemaInPrompt: Bool?
        var reasoningLevel: ReasoningLevel?
    }

    /// Upper bound for `reasoningLevel.custom` values. The string is forwarded
    /// verbatim to the native runtime — the bridge never concatenates it into a
    /// prompt — so the cap only bounds abuse (threat model, DES-0058).
    private static let maxCustomReasoningLevelLength = 256

    /// Internal (not `private`) as a test seam — the system-model call sites
    /// need Apple Intelligence to run, so the fail-fast validation is pinned
    /// directly by unit tests via `@testable import` (same spirit as
    /// `mlxBackendOverride`).
    func contextOptionsParams(params: [String: Any]) throws -> ContextOptionsParams? {
        guard let raw = JSON.object(params, key: "contextOptions") else {
            return nil
        }

        var parsed = ContextOptionsParams()

        if let include = raw["includeSchemaInPrompt"] {
            guard let bool = include as? Bool else {
                throw JsonRpcError.invalidRequest("contextOptions.includeSchemaInPrompt must be a boolean.")
            }
            parsed.includeSchemaInPrompt = bool
        }

        if let level = raw["reasoningLevel"] {
            parsed.reasoningLevel = try reasoningLevel(from: level)
        }

        return parsed
    }

    func reasoningLevel(from value: Any) throws -> ContextOptionsParams.ReasoningLevel {
        if let name = value as? String {
            switch name {
            case "light":
                return .light
            case "moderate":
                return .moderate
            case "deep":
                return .deep
            default:
                throw JsonRpcError.invalidRequest(
                    "contextOptions.reasoningLevel must be \"light\", \"moderate\", \"deep\", or { \"custom\": <string> }."
                )
            }
        }

        if let object = value as? [String: Any], let custom = object["custom"] {
            guard let text = custom as? String, !text.isEmpty else {
                throw JsonRpcError.invalidRequest("contextOptions.reasoningLevel.custom must be a non-empty string.")
            }
            guard text.count <= Self.maxCustomReasoningLevelLength else {
                throw JsonRpcError.invalidRequest(
                    "contextOptions.reasoningLevel.custom must be at most \(Self.maxCustomReasoningLevelLength) characters."
                )
            }
            return .custom(text)
        }

        throw JsonRpcError.invalidRequest(
            "contextOptions.reasoningLevel must be \"light\", \"moderate\", \"deep\", or { \"custom\": <string> }."
        )
    }

    private func contextOptionsUnavailableError() -> JsonRpcError {
        JsonRpcError.unsupported(
            "contextOptions requires macOS 27 or newer.",
            data: ["code": "UNSUPPORTED_OPTION", "option": "contextOptions"]
        )
    }

    /// Direct-path models (`apple.mlx:*` respond/stream, `apple.coreai:*` direct
    /// generation) bypass `LanguageModelSession`, so session-scoped options have
    /// nowhere to apply. Rejecting them keeps the contract honest instead of
    /// silently ignoring caller intent (DES-0058).
    ///
    /// `tools` joined this list in FND-0166 / TCK-0212: none of the direct-path
    /// generators (`generateTextMLXDirect`, `generateStructuredOutputMLXDirect`,
    /// `generateVisionTextMLXDirect`, `generateTextCoreAIDirect`, and their
    /// streaming counterparts) ever reads `params["tools"]`, so a caller
    /// attaching tools to `apple.mlx:*`/`apple.coreai:*` respond/stream had them
    /// discarded with no error, even though `availability()` reports
    /// `supports.toolCalling: true` for these model ids
    /// (`CoreAIModelRegistry.swift`). DECISION: reject naming the offending
    /// tools rather than flip `supports.toolCalling` to `false` — `sessions.create`
    /// for these same model ids already wires tools correctly through a real
    /// `LanguageModelSession` (see `buildSession`'s `CoreAIModelRegistry.isCoreAIModelId`
    /// branch); the gap is this respond/stream shortcut bypassing that session,
    /// not a model-level incapacity. See docs/parity.md (Tool calling row) for
    /// the full rationale.
    private func rejectSessionOnlyOptions(params: [String: Any], modelId: String) throws {
        var unsupported = ["contextOptions", "transcriptErrorHandlingPolicy"].filter { params[$0] != nil }
        let toolNames = (JSON.array(params, key: "tools") ?? []).compactMap { JSON.string($0, key: "name") }
        if !toolNames.isEmpty {
            unsupported.append("tools")
        }

        guard unsupported.isEmpty else {
            let toolsSuffix = toolNames.isEmpty ? "" : " (tools: \(toolNames.joined(separator: ", ")))"
            var data: [String: Any] = [
                "code": "UNSUPPORTED_OPTION",
                "model": modelId,
                "options": unsupported
            ]
            if !toolNames.isEmpty {
                data["tools"] = toolNames
            }

            throw JsonRpcError.unsupported(
                "\(unsupported.joined(separator: ", ")) not supported for direct-path model \(modelId) (bypasses LanguageModelSession)\(toolsSuffix).",
                data: data
            )
        }
    }

    #if canImport(FoundationModels)
    /// Maps native Foundation Models generation errors to stable JSON-RPC errors.
    ///
    /// Arm order is load-bearing:
    ///
    /// 1. **Pass-through** of an already-typed `JsonRpcError`. Call sites now
    ///    route schema compilation through this mapper too (TCK-0208), and
    ///    without this guard the string heuristic below could rewrite our own
    ///    contract errors.
    /// 2. `PrivateCloudComputeLanguageModel.Error` (PCC family, `-32010`),
    ///    specialized by `reasonCode` (FND-0203).
    /// 3. `LanguageModelSession.ToolCallError` → `TOOL_EXECUTION_FAILED`
    ///    carrying the failing tool name (TCK-0015c).
    /// 4. The **typed** macOS 27 errors — `LanguageModelError`,
    ///    `LanguageModelSession.Error`, `SystemLanguageModel.Error`,
    ///    `GenerationSchema.SchemaError`, `GeneratedContent.ParsingError`.
    ///    These MUST come before the string heuristic: a typed
    ///    `contextSizeExceeded` caught by `looksLikeContextOverflow` would
    ///    silently lose its `contextSize`/`tokenCount` payload.
    /// 5. `looksLikeContextOverflow` — the string heuristic. It is the primary
    ///    path on macOS 26, and on macOS 27 it still runs for any error the
    ///    typed mapping in (4) did not match (it returns nil outside the five
    ///    families above). It is demoted, not eliminated.
    /// 6. The deprecated `LanguageModelSession.GenerationError`, expanded to
    ///    emit exactly the same contract codes as their macOS 27 replacements
    ///    (per the SDK's own deprecation map) so the wire contract does not
    ///    depend on the host OS version.
    ///
    /// Anything else passes through unchanged.
    @available(macOS 26.0, *)
    private func mapNativeGenerationError(_ error: Error, params: [String: Any] = [:]) -> Error {
        // (1) Never re-wrap an error that already carries a contract code.
        if let alreadyTyped = error as? JsonRpcError {
            return alreadyTyped
        }

        if #available(macOS 27.0, *),
           let pccError = error as? PrivateCloudComputeLanguageModel.Error {
            switch pccError {
            case .quotaLimitReached(let details):
                var data: [String: Any] = [
                    "code": "PCC_QUOTA_EXHAUSTED",
                    "reason": details.debugDescription
                ]
                if let resetDate = details.resetDate {
                    data["resetDate"] = ISO8601DateFormatter().string(from: resetDate)
                }
                if details.limitIncreaseSuggestion != nil {
                    data["limitIncreaseSuggestion"] = true
                }
                return JsonRpcError.modelUnavailable(
                    "Private Cloud Compute quota is exhausted.",
                    data: data
                )
            // TCK-0208 / FND-0203 — the PCC failure granularity is ADDITIVE:
            // `reasonCode` stays the already-published `"pcc_unavailable"` for
            // every PCC arm (consumers switch on it), and the new
            // `pccFailureKind` + `retryable` fields carry the distinction.
            case .networkFailure(let details):
                return JsonRpcError.modelUnavailable(
                    "Private Cloud Compute network failure.",
                    data: [
                        "code": "PCC_UNAVAILABLE",
                        "reason": details.debugDescription,
                        "reasonCode": "pcc_unavailable",
                        "pccFailureKind": "network_failure",
                        "retryable": true
                    ]
                )
            case .serviceUnavailable(let details):
                return JsonRpcError.modelUnavailable(
                    "Private Cloud Compute service is unavailable.",
                    data: [
                        "code": "PCC_UNAVAILABLE",
                        "reason": details.debugDescription,
                        "reasonCode": "pcc_unavailable",
                        "pccFailureKind": "service_unavailable",
                        "retryable": true
                    ]
                )
            @unknown default:
                return JsonRpcError.modelUnavailable(
                    "Private Cloud Compute is unavailable.",
                    data: ["code": "PCC_UNAVAILABLE", "reasonCode": "pcc_unavailable"]
                )
            }
        }

        if let toolCallError = error as? LanguageModelSession.ToolCallError {
            // The callback bridge already throws a typed JsonRpcError with the
            // tool payload; unwrap it instead of double-wrapping.
            if let bridgeError = toolCallError.underlyingError as? JsonRpcError {
                return bridgeError
            }

            let toolName = toolCallError.tool.name
            let reason = toolCallError.underlyingError.localizedDescription
            return JsonRpcError.toolExecutionFailed(
                "Tool \"\(toolName)\" failed during generation: \(reason)",
                data: [
                    "code": "TOOL_EXECUTION_FAILED",
                    "toolName": toolName,
                    "message": reason
                ]
            )
        }

        if #available(macOS 27.0, *), let typed = mapTypedNativeError(error, params: params) {
            return typed
        }

        // (5) String heuristic. On macOS 27 a context overflow normally arrives
        // as the typed `LanguageModelError.contextSizeExceeded` handled above
        // (with the `contextSize`/`tokenCount` payload this heuristic cannot
        // recover), so this arm is reached there only when the typed mapping
        // returned nil — i.e. an error outside the five typed families. On
        // macOS 26 it remains the primary detection path.
        if looksLikeContextOverflow(error) {
            return NativeErrorContract.contextSizeExceeded(reason: error.localizedDescription)
        }

        guard let generationError = error as? LanguageModelSession.GenerationError else {
            return error
        }

        // (6) Deprecated macOS 26 enum. Each arm mirrors the replacement named
        // by the SDK's own `@available(..., deprecated: 27.0, message:)`
        // annotations, so a client sees the same `data.code` on macOS 26 and 27.
        switch generationError {
        case .exceededContextWindowSize(let context):
            return NativeErrorContract.contextSizeExceeded(reason: context.debugDescription)
        case .assetsUnavailable(let context):
            return NativeErrorContract.assetsUnavailable(reason: context.debugDescription)
        case .guardrailViolation(let context):
            return NativeErrorContract.guardrailViolation(reason: context.debugDescription)
        case .unsupportedGuide(let context):
            return NativeErrorContract.unsupportedGenerationGuide(reason: context.debugDescription)
        case .unsupportedLanguageOrLocale(let context):
            return NativeErrorContract.unsupportedLanguageOrLocale(reason: context.debugDescription)
        case .decodingFailure(let context):
            return NativeErrorContract.parsingError(reason: context.debugDescription)
        case .rateLimited(let context):
            return NativeErrorContract.rateLimited(reason: context.debugDescription)
        case .concurrentRequests(let context):
            return NativeErrorContract.sessionBusy(reason: context.debugDescription)
        case .refusal(_, let context):
            // The `Refusal` payload is `[Transcript.Entry]` — raw prompt
            // content. Only the context's debug description crosses the wire.
            return NativeErrorContract.refusal(reason: context.debugDescription)
        default:
            return error
        }
    }

    /// Casts against the macOS 27 typed error families and extracts the
    /// scalars the contract forwards. Returns `nil` when `error` belongs to
    /// none of them, so the caller can fall through to the macOS 26 arms.
    ///
    /// Only typed scalars and the native `debugDescription` are read: the
    /// untyped `metadata` bag, the raw `[Transcript.Entry]` payloads, and
    /// `ParsingError.rawContent` are never forwarded (TCK-0208 R1).
    @available(macOS 27.0, *)
    private func mapTypedNativeError(_ error: Error, params: [String: Any]) -> JsonRpcError? {
        if let modelError = error as? LanguageModelError {
            switch modelError {
            case .contextSizeExceeded(let details):
                return NativeErrorContract.contextSizeExceeded(
                    contextSize: details.contextSize,
                    tokenCount: details.tokenCount,
                    reason: details.debugDescription
                )
            case .rateLimited(let details):
                return NativeErrorContract.rateLimited(
                    resetDate: details.resetDate,
                    reason: details.debugDescription
                )
            case .guardrailViolation(let details):
                return NativeErrorContract.guardrailViolation(reason: details.debugDescription)
            case .refusal(let details):
                return NativeErrorContract.refusal(reason: details.debugDescription)
            case .unsupportedCapability(let details):
                let capability = capabilityName(details.capability)
                if capability == "vision" {
                    return NativeErrorContract.unsupportedVisionCapability(
                        model: JSON.string(params, key: "model") ?? "apple.system",
                        reason: details.debugDescription
                    )
                }
                return NativeErrorContract.unsupportedCapability(
                    capability: capability,
                    reason: details.debugDescription
                )
            case .unsupportedTranscriptContent(let details):
                return NativeErrorContract.unsupportedTranscriptContent(
                    entryCount: details.unsupportedContent.count,
                    reason: details.debugDescription
                )
            case .unsupportedGenerationGuide(let details):
                return NativeErrorContract.unsupportedGenerationGuide(
                    schemaName: details.schemaName,
                    reason: details.debugDescription
                )
            case .unsupportedLanguageOrLocale(let details):
                return NativeErrorContract.unsupportedLanguageOrLocale(
                    languageCode: details.languageCode.identifier,
                    reason: details.debugDescription
                )
            case .timeout(let details):
                return NativeErrorContract.timeout(reason: details.debugDescription)
            @unknown default:
                return NativeErrorContract.unknownModelError(reason: modelError.debugDescription)
            }
        }

        if let sessionError = error as? LanguageModelSession.Error {
            switch sessionError {
            case .concurrentRequests:
                return NativeErrorContract.sessionBusy(reason: sessionError.debugDescription)
            case .transcriptMutationWhileResponding:
                return NativeErrorContract.transcriptMutationWhileResponding(
                    reason: sessionError.debugDescription
                )
            @unknown default:
                return NativeErrorContract.unknownModelError(reason: sessionError.debugDescription)
            }
        }

        if let systemError = error as? SystemLanguageModel.Error {
            switch systemError {
            case .assetsUnavailable(let details):
                return NativeErrorContract.assetsUnavailable(reason: details.debugDescription)
            @unknown default:
                return NativeErrorContract.unknownModelError(reason: systemError.debugDescription)
            }
        }

        if let schemaError = error as? GenerationSchema.SchemaError {
            switch schemaError {
            case .duplicateType(let schema, let type, let context):
                return NativeErrorContract.schemaError(
                    schemaErrorCase: "duplicateType",
                    schema: schema,
                    property: type,
                    reason: context.debugDescription
                )
            case .duplicateProperty(let schema, let property, let context):
                return NativeErrorContract.schemaError(
                    schemaErrorCase: "duplicateProperty",
                    schema: schema,
                    property: property,
                    reason: context.debugDescription
                )
            case .emptyTypeChoices(let schema, let context):
                return NativeErrorContract.schemaError(
                    schemaErrorCase: "emptyTypeChoices",
                    schema: schema,
                    reason: context.debugDescription
                )
            case .undefinedReferences(let schema, let references, let context):
                return NativeErrorContract.schemaError(
                    schemaErrorCase: "undefinedReferences",
                    schema: schema,
                    references: references,
                    reason: context.debugDescription
                )
            @unknown default:
                return NativeErrorContract.unknownModelError(reason: schemaError.localizedDescription)
            }
        }

        if let parsingError = error as? GeneratedContent.ParsingError {
            // `parsingError.rawContent` is unvalidated model output — never
            // forwarded (R1).
            return NativeErrorContract.parsingError(reason: parsingError.debugDescription)
        }

        return nil
    }

    /// Stable string name for a `LanguageModelCapabilities.Capability`. The
    /// type is an opaque `Hashable` struct with static members, so the only
    /// available discriminator is `==` against the known capabilities.
    @available(macOS 27.0, *)
    private func capabilityName(_ capability: LanguageModelCapabilities.Capability) -> String {
        switch capability {
        case .vision: return "vision"
        case .guidedGeneration: return "guidedGeneration"
        case .reasoning: return "reasoning"
        case .toolCalling: return "toolCalling"
        default: return "unknown"
        }
    }

    /// Heuristic string match for a context overflow, used **only** as a
    /// String heuristic, kept as the detection path on macOS 26. On macOS 27 the
    /// condition normally arrives as the typed `LanguageModelError.contextSizeExceeded`,
    /// matched earlier in `mapNativeGenerationError` with real token counts — but
    /// this heuristic is still consulted there for errors the typed mapping does
    /// not recognise, so it is a demoted path rather than a version-gated one.
    @available(macOS 26.0, *)
    private func looksLikeContextOverflow(_ error: Error) -> Bool {
        let description = "\(type(of: error)) \(error.localizedDescription) \(String(describing: error))"
            .lowercased()

        return description.contains("exceeded")
            && (description.contains("context size") || description.contains("context window"))
    }

    @available(macOS 26.0, *)
    private func sessionFor(params: [String: Any], toolBridge: Any?) throws -> LanguageModelSession {
        if hasCallbackTools(params: params) {
            return try makeSession(params: params, toolBridge: toolBridge)
        }

        guard let sessionId = JSON.string(params, key: "sessionId") else {
            return try makeSession(params: params, toolBridge: toolBridge)
        }

        if let existing = sessionRegistry.get(sessionId) as? LanguageModelSession {
            return existing
        }

        let session = try makeSession(params: params, toolBridge: toolBridge)
        sessionRegistry.set(sessionId, session)
        // Tracked here (not just in `createSession`) because respond/stream is the
        // path that ACTUALLY creates most native sessions in practice — the wire
        // `foundationmodels.sessions.create` is lazy-equivalent to this. Without
        // this, `transitionSession` (TCK-0213 / FND-0156) would have no build
        // params to rebuild from for the common case and would silently default
        // to the wrong model branch.
        sessionBuildParams.set(sessionId, params)
        return session
    }

    @available(macOS 26.0, *)
    private func makeSession(params: [String: Any], toolBridge: Any? = nil, transcript: Transcript? = nil) throws -> LanguageModelSession {
        let session = try buildSession(params: params, toolBridge: toolBridge, transcript: transcript)
        try applyTranscriptErrorHandlingPolicy(to: session, params: params)
        return session
    }

    /// Applies the request `transcriptErrorHandlingPolicy` to a freshly built
    /// native session (TCK-0205 / DES-0058). The SDK 27 surface exposes the
    /// policy as a settable session property (`{ get set }`) — no init accepts
    /// it — so a single post-construction assignment covers the CoreAI / PCC /
    /// system branches alike.
    @available(macOS 26.0, *)
    private func applyTranscriptErrorHandlingPolicy(to session: LanguageModelSession, params: [String: Any]) throws {
        guard let raw = JSON.string(params, key: "transcriptErrorHandlingPolicy") else {
            return
        }

        guard #available(macOS 27.0, *) else {
            throw JsonRpcError.unsupported(
                "transcriptErrorHandlingPolicy requires macOS 27 or newer.",
                data: ["code": "UNSUPPORTED_OPTION", "option": "transcriptErrorHandlingPolicy"]
            )
        }

        session.transcriptErrorHandlingPolicy = try Self.transcriptErrorHandlingPolicy(from: raw)
    }

    /// Internal (not `private`) as a test seam — see `contextOptionsParams`.
    @available(macOS 27.0, *)
    static func transcriptErrorHandlingPolicy(from raw: String) throws -> TranscriptErrorHandlingPolicy {
        switch raw {
        case "revert":
            return .revertTranscript
        case "preserve":
            return .preserveTranscript
        default:
            throw JsonRpcError.invalidRequest("transcriptErrorHandlingPolicy must be \"revert\" or \"preserve\".")
        }
    }

    /// Maps validated `ContextOptionsParams` to the native SDK 27 struct.
    /// `includeSchemaInPromptDefault` preserves the pre-TCK-0205 behavior of
    /// the guided-generation call sites (hardcoded `true`) when the caller does
    /// not state a preference.
    @available(macOS 27.0, *)
    private func nativeContextOptions(
        _ parsed: ContextOptionsParams,
        includeSchemaInPromptDefault: Bool? = nil
    ) -> ContextOptions {
        let level: ContextOptions.ReasoningLevel?
        switch parsed.reasoningLevel {
        case .light:
            level = .light
        case .moderate:
            level = .moderate
        case .deep:
            level = .deep
        case .custom(let value):
            level = .custom(value)
        case nil:
            level = nil
        }

        return ContextOptions(
            includeSchemaInPrompt: parsed.includeSchemaInPrompt ?? includeSchemaInPromptDefault,
            reasoningLevel: level
        )
    }

    /// Builds a native session. `transcript`, when non-nil, is used INSTEAD of
    /// `instructions:` — via `LanguageModelSession(model:tools:transcript:)` —
    /// so the caller (`createSession` with a `history` seed, or
    /// `transitionSession` rebuilding with preserved history) controls the
    /// full prior conversation rather than starting from a blank transcript
    /// (TCK-0213 / FND-0205 / FND-0156).
    @available(macOS 26.0, *)
    private func buildSession(params: [String: Any], toolBridge: Any? = nil, transcript: Transcript? = nil) throws -> LanguageModelSession {
        if let modelId = JSON.string(params, key: "model"),
           CoreAIModelRegistry.isCoreAIModelId(modelId) {
            guard let registeredModel = CoreAIModelRegistry.model(id: modelId) else {
                throw CoreAIModelRegistry.requestError(for: modelId)
            }

            if #available(macOS 27.0, *) {
                let model = CoreAILanguageModel(id: modelId, registryPath: registeredModel.path)
                let tools = try nativeTools(params: params, toolBridge: toolBridge)
                if let transcript {
                    return LanguageModelSession(model: model, tools: tools, transcript: transcript)
                }
                return LanguageModelSession(model: model, tools: tools, instructions: JSON.string(params, key: "instructions"))
            }

            throw JsonRpcError.modelUnavailable(
                "Core AI LanguageModelExecutor requires macOS 27 or newer.",
                data: ["code": "INFERENCE_BACKEND_UNAVAILABLE", "model": modelId, "reasonCode": "inference_backend_unavailable"]
            )
        }

        if JSON.string(params, key: "model") == "apple.pcc" {
            if #available(macOS 27.0, *) {
                let model = try pccLanguageModel()
                let tools = try nativeTools(params: params, toolBridge: toolBridge)
                if let transcript {
                    return LanguageModelSession(model: model, tools: tools, transcript: transcript)
                }
                return LanguageModelSession(model: model, tools: tools, instructions: JSON.string(params, key: "instructions"))
            }

            throw JsonRpcError.modelUnavailable(
                "Private Cloud Compute requires macOS 27 or newer.",
                data: ["code": "PCC_UNAVAILABLE", "reasonCode": "pcc_unavailable"]
            )
        }

        let model = try systemLanguageModel(params: params)
        let tools = try nativeTools(params: params, toolBridge: toolBridge)
        if let transcript {
            return LanguageModelSession(model: model, tools: tools, transcript: transcript)
        }
        return LanguageModelSession(model: model, tools: tools, instructions: JSON.string(params, key: "instructions"))
    }

    /// Maps a `foundationmodels.sessions.create` `history` param (array of
    /// `{ role: "user" | "assistant", content: string }` turns) plus an optional
    /// `instructions` string into a native `Transcript` (TCK-0213 / FND-0205).
    /// Returns `nil` when no history was requested, preserving the exact prior
    /// `instructions:`-based construction path byte for byte. Malformed or
    /// unsupported turns fail fast — silently dropping a turn would just trade
    /// one "claims more than it did" bug for another.
    ///
    /// Internal (not `private`) as a test seam, same rationale as
    /// `transcriptErrorHandlingPolicy(from:)` above: this environment's `swift
    /// test` can't reach a real `LanguageModelSession` (no Apple Intelligence
    /// eligibility), but this is a pure `[String: Any]` → `Transcript` mapping
    /// with no device dependency, so it's exercisable directly.
    @available(macOS 26.0, *)
    static func historyTranscript(params: [String: Any]) throws -> Transcript? {
        guard let rawHistory = JSON.array(params, key: "history"), !rawHistory.isEmpty else {
            return nil
        }

        var entries: [Transcript.Entry] = []
        if let instructions = JSON.string(params, key: "instructions") {
            entries.append(
                .instructions(
                    Transcript.Instructions(
                        segments: [.text(Transcript.TextSegment(content: instructions))],
                        toolDefinitions: []
                    )
                )
            )
        }

        for turn in rawHistory {
            guard let role = JSON.string(turn, key: "role") else {
                throw JsonRpcError.invalidRequest("Each history turn requires a \"role\".")
            }
            guard let content = JSON.string(turn, key: "content") else {
                throw JsonRpcError.invalidRequest("Each history turn requires \"content\".")
            }

            switch role {
            case "user":
                entries.append(.prompt(Transcript.Prompt(segments: [.text(Transcript.TextSegment(content: content))])))
            case "assistant":
                entries.append(.response(Transcript.Response(assetIDs: [], segments: [.text(Transcript.TextSegment(content: content))])))
            default:
                throw JsonRpcError.invalidRequest(
                    "Unsupported history turn role \"\(role)\". Expected \"user\" or \"assistant\"."
                )
            }
        }

        return Transcript(entries: entries)
    }

    /// Returns a copy of `transcript` with its `.instructions` entry replaced by
    /// `text` (inserted at the front if none existed), preserving every other
    /// entry — prompts, responses, tool calls/output — byte for byte (TCK-0213 /
    /// FND-0156). Existing `toolDefinitions` are carried over unchanged: a
    /// transition only ever supplies `profile`/`instructions`, never `tools`.
    /// Internal (not `private`) as a test seam — see `historyTranscript` above.
    @available(macOS 26.0, *)
    static func rebuildTranscript(_ transcript: Transcript, replacingInstructionsWith text: String) -> Transcript {
        var entries = Array(transcript)

        var toolDefinitions: [Transcript.ToolDefinition] = []
        if let index = entries.firstIndex(where: { entry in
            if case .instructions = entry { return true }
            return false
        }) {
            if case .instructions(let existing) = entries[index] {
                toolDefinitions = existing.toolDefinitions
            }
            entries[index] = .instructions(
                Transcript.Instructions(
                    segments: [.text(Transcript.TextSegment(content: text))],
                    toolDefinitions: toolDefinitions
                )
            )
        } else {
            entries.insert(
                .instructions(
                    Transcript.Instructions(
                        segments: [.text(Transcript.TextSegment(content: text))],
                        toolDefinitions: toolDefinitions
                    )
                ),
                at: 0
            )
        }

        return Transcript(entries: entries)
    }

    @available(macOS 26.0, *)
    private func systemLanguageModel(params: [String: Any]) throws -> SystemLanguageModel {
        try SystemLanguageModel(
            useCase: systemUseCase(params: params),
            guardrails: systemGuardrails(params: params)
        )
    }

    @available(macOS 26.0, *)
    private func systemUseCase(params: [String: Any]) throws -> SystemLanguageModel.UseCase {
        guard let useCase = JSON.string(params, key: "useCase") else {
            return .general
        }

        switch useCase {
        case "general":
            return .general
        case "contentTagging":
            return .contentTagging
        default:
            throw JsonRpcError.invalidRequest("Unsupported useCase: \(useCase).")
        }
    }

    @available(macOS 26.0, *)
    private func systemGuardrails(params: [String: Any]) throws -> SystemLanguageModel.Guardrails {
        guard let guardrails = JSON.string(params, key: "guardrails") else {
            return .default
        }

        switch guardrails {
        case "default":
            return .default
        case "permissive":
            return .permissiveContentTransformations
        default:
            throw JsonRpcError.invalidRequest("Unsupported guardrails: \(guardrails).")
        }
    }

    @available(macOS 27.0, *)
    private func pccLanguageModel() throws -> PrivateCloudComputeLanguageModel {
        // TCK-0105 — pre-flight entitlement guard (PCC typed-unavailable path).
        //
        // The FoundationModels SDK raises a fatal precondition ("Process is missing
        // required entitlement: com.apple.developer.private-cloud-compute") at
        // inference time when the daemon binary is not code-signed with the PCC
        // entitlement. A Swift `try/catch` cannot intercept `fatalError`/
        // `preconditionFailure` — they abort the process. This guard uses
        // `SecTaskCopyValueForEntitlement` to check the entitlement on the current
        // process BEFORE constructing a session and reaching inference, so that the
        // unentitled path surfaces a typed JSON-RPC error (code -32010,
        // `data.code` PCC_UNAVAILABLE, `data.reasonCode` "pcc_unavailable", plus
        // the TCK-0208 granularity fields `data.pccFailureKind`
        // "missing_entitlement" and `data.retryable` false) and the daemon
        // remains alive instead of crashing and dropping the socket.
        //
        // If the check is inconclusive (Security framework error) we proceed and
        // let the SDK's own availability check fire — this is the fail-open path
        // that existed before TCK-0105, but is now reached only when the
        // entitlement query itself fails, not on a clearly unentitled build.
        //
        // See: docs/pcc-entitlement.md for provisioning steps.
        guard processPCCEntitlementPresent() else {
            throw JsonRpcError.modelUnavailable(
                "Private Cloud Compute is unavailable: process is missing the " +
                    "com.apple.developer.private-cloud-compute entitlement. " +
                    "See docs/pcc-entitlement.md for provisioning steps.",
                data: [
                    "code": "PCC_UNAVAILABLE",
                    "reason": "missingEntitlement",
                    "reasonCode": "pcc_unavailable",
                    "pccFailureKind": "missing_entitlement",
                    "retryable": false
                ]
            )
        }

        let model = PrivateCloudComputeLanguageModel()
        switch model.availability {
        case .available:
            let quota = model.quotaUsage
            if quota.isLimitReached {
                throw JsonRpcError.modelUnavailable(
                    "Private Cloud Compute quota is exhausted.",
                    data: [
                        "code": "PCC_QUOTA_EXHAUSTED",
                        "pccQuota": pccQuotaDict(quota)
                    ]
                )
            }
            return model
        case .unavailable(let reason):
            throw JsonRpcError.modelUnavailable(
                "Private Cloud Compute is unavailable.",
                data: [
                    "code": "PCC_UNAVAILABLE",
                    "reason": String(describing: reason),
                    "reasonCode": "pcc_unavailable"
                ]
            )
        @unknown default:
            throw JsonRpcError.modelUnavailable(
                "Private Cloud Compute is unavailable.",
                data: ["code": "PCC_UNAVAILABLE", "reasonCode": "pcc_unavailable"]
            )
        }
    }

    @available(macOS 26.0, *)
    private func nativeTools(params: [String: Any], toolBridge: Any?) throws -> [any Tool] {
        try (JSON.array(params, key: "tools") ?? []).map { tool in
            // TCK-0227 / FND-0147: Apple's own vision tools. These conform to
            // `FoundationModels.Tool` and the MODEL decides to invoke them
            // mid-generation; the framework executes them in-process. They carry
            // their own `Arguments` schema (`{ image: ImageReference }`), so a
            // caller-supplied `inputSchema` is neither required nor meaningful —
            // which is why this branch runs before the schema guard below.
            if let native = JSON.string(tool, key: "native") {
                return try nativeVisionTool(
                    kind: native,
                    name: JSON.string(tool, key: "name"),
                    description: JSON.string(tool, key: "description")
                )
            }

            guard let inputSchema = tool["inputSchema"] as? [String: Any] else {
                throw JsonRpcError.invalidRequest("Tool inputSchema must be a JSON Schema object.")
            }
            let usesCallback = JSON.bool(tool, key: "callback") == true
            let bridge = toolBridge as? ToolCallbackBridge
            if usesCallback && bridge == nil {
                throw callbackToolsRequireStreamingError(params: params)
            }

            return BridgeTool(
                name: JSON.string(tool, key: "name") ?? "",
                description: JSON.string(tool, key: "description") ?? "",
                parameters: try generationSchema(from: inputSchema),
                output: usesCallback ? nil : textForToolOutput(tool["staticOutput"] ?? ""),
                callbackBridge: usesCallback ? bridge : nil,
                // FND-0207 / TCK-0212: per-tool knob for the native
                // `Tool.includesSchemaInInstructions` requirement. Defaults to
                // `true` when the wire omits the field — matches both the SDK's
                // own protocol-extension default (`FoundationModels.swiftinterface:2520`)
                // and this bridge's pre-existing hardcoded behavior, so absent
                // callers see no change (ratchet P9).
                includesSchemaInInstructions: JSON.bool(tool, key: "includesSchemaInInstructions") ?? true
            )
        }
    }

    /// Maps `options` to native `GenerationOptions` (FND-0163 / TCK-0212).
    /// Uses the SDK 27 NON-deprecated initializer
    /// (`init(samplingMode:temperature:maximumResponseTokens:...)`, label
    /// `samplingMode:`) instead of the deprecated `init(sampling:...)`
    /// (`@available(*, deprecated, renamed:
    /// "init(samplingMode:temperature:maximumResponseTokens:)")` per
    /// `FoundationModels.swiftinterface`). The `samplingMode:` overload
    /// without `toolCallingMode` is `@backDeployed` to macOS 26, so absent
    /// `toolCallingMode` keeps working there byte for byte; only the
    /// four-argument overload that adds `toolCallingMode:` requires macOS 27.
    @available(macOS 26.0, *)
    private func generationOptions(params: [String: Any]) throws -> GenerationOptions {
        let options = JSON.object(params, key: "options") ?? [:]
        let sampling = try samplingMode(options: options)
        let temperature = JSON.double(options, key: "temperature")
        let maximumResponseTokens = JSON.int(options, key: "maximumResponseTokens")

        guard let toolCallingModeRaw = JSON.string(options, key: "toolCallingMode") else {
            return GenerationOptions(
                samplingMode: sampling,
                temperature: temperature,
                maximumResponseTokens: maximumResponseTokens
            )
        }

        guard #available(macOS 27.0, *) else {
            throw JsonRpcError.unsupported(
                "options.toolCallingMode requires macOS 27 or newer.",
                data: ["code": "UNSUPPORTED_OPTION", "option": "toolCallingMode"]
            )
        }

        return GenerationOptions(
            samplingMode: sampling,
            temperature: temperature,
            maximumResponseTokens: maximumResponseTokens,
            toolCallingMode: try Self.toolCallingMode(from: toolCallingModeRaw)
        )
    }

    /// Maps the validated `options.toolCallingMode` string to the SDK 27
    /// `GenerationOptions.ToolCallingMode` (FND-0163). Mirrors the three
    /// native `Kind` cases (`.allowed`/`.required`/`.disallowed`,
    /// `FoundationModels.swiftinterface:2718-2733`). Internal (not
    /// `private`) as a test seam — see `transcriptErrorHandlingPolicy`.
    @available(macOS 27.0, *)
    static func toolCallingMode(from raw: String) throws -> GenerationOptions.ToolCallingMode {
        switch raw {
        case "allowed":
            return .allowed
        case "required":
            return .required
        case "disallowed":
            return .disallowed
        default:
            throw JsonRpcError.invalidRequest(
                "options.toolCallingMode must be \"allowed\", \"required\", or \"disallowed\"."
            )
        }
    }

    @available(macOS 26.0, *)
    private func samplingMode(options: [String: Any]) throws -> GenerationOptions.SamplingMode? {
        guard let sampling = JSON.object(options, key: "sampling") else {
            return nil
        }

        switch JSON.string(sampling, key: "mode") {
        case "greedy":
            return .greedy
        case "top_k":
            guard let topK = JSON.int(sampling, key: "topK"), topK > 0 else {
                throw JsonRpcError.invalidRequest("options.sampling.topK must be a positive integer.")
            }
            return .random(top: topK, seed: try samplingSeed(sampling))
        case "top_p":
            guard let threshold = JSON.double(sampling, key: "probabilityThreshold"),
                  threshold > 0,
                  threshold <= 1 else {
                throw JsonRpcError.invalidRequest("options.sampling.probabilityThreshold must be greater than 0 and at most 1.")
            }
            return .random(probabilityThreshold: threshold, seed: try samplingSeed(sampling))
        case .some(let mode):
            throw JsonRpcError.invalidRequest("Unsupported options.sampling.mode: \(mode).")
        case .none:
            throw JsonRpcError.invalidRequest("options.sampling.mode is required when sampling is provided.")
        }
    }

    private func samplingSeed(_ sampling: [String: Any]) throws -> UInt64? {
        guard let seed = JSON.int(sampling, key: "seed") else {
            return nil
        }
        guard seed >= 0 else {
            throw JsonRpcError.invalidRequest("options.sampling.seed must be a non-negative integer.")
        }
        return UInt64(seed)
    }

    /// JSON Schema keywords the native `DynamicGenerationSchema` mapping cannot
    /// honor. Every keyword here changes which outputs are valid, so silently
    /// dropping one would let guided generation return data that violates the
    /// requested schema. The daemon fails fast instead, with a typed
    /// `UNSUPPORTED_SCHEMA_TYPE` error naming the keyword and its schema path.
    ///
    /// `const` is deliberately absent from this blanket list (TCK-0215 /
    /// FND-0146): unlike every keyword here, Apple exposes a real guide for it
    /// on strings (`GenerationGuide<String>.constant`, SDK 27 swiftinterface
    /// L1121, `@available(macOS 26.0, *)`), so it is validated case-by-case in
    /// `ensureSupportedSchemaKeywords` below instead of always rejected.
    private static let unsupportedSchemaKeywords: [String] = [
        "$dynamicRef", "$dynamicAnchor",
        "allOf", "oneOf", "not", "if", "then", "else",
        "patternProperties", "propertyNames", "dependentRequired", "dependentSchemas",
        "unevaluatedProperties", "minProperties", "maxProperties",
        "prefixItems", "contains", "unevaluatedItems", "uniqueItems",
        "format", "minLength", "maxLength",
        "exclusiveMinimum", "exclusiveMaximum", "multipleOf"
    ]

    private func ensureSupportedSchemaKeywords(_ schema: [String: Any], path: String) throws {
        if let keyword = Self.unsupportedSchemaKeywords.first(where: { schema[$0] != nil }) {
            throw unsupportedSchemaKeywordError(keyword, path: path)
        }

        // FND-0146: `const` maps 1:1 onto `GenerationGuide<String>.constant`
        // only for string schemas — the only type Apple exposes a `.constant`
        // guide for (see the type-list above). Every other type/shape (or a
        // non-string const value) has no native equivalent and stays a hard
        // rejection, same as before this fix. The actual mapping happens in
        // `stringGenerationSchema`.
        if let constValue = schema["const"], !(jsonSchemaType(schema) == "string" && constValue is String) {
            throw unsupportedSchemaKeywordError("const", path: path)
        }

        // FND-0145 / TCK-0233: a `type` array containing `"null"` used to be
        // silently narrowed to its first non-null member by `jsonSchemaType`
        // below. Do NOT peel here. Mappable shapes
        // (`["string","null"]` and siblings with exactly one non-null member)
        // are handled in `dynamicGenerationSchema` via
        // `anyOf: [typeSchema, .null]` (DES-0083). Unmappable shapes still
        // reject by name — never drop the null branch without a diagnostic.
        // (`representNilExplicitlyInGeneratedContent` is a separate
        // object-scoped axis for optional properties and is not used here.)
        if let types = schema["type"] as? [String], types.contains("null") {
            let nonNull = Set(types.filter { $0 != "null" })
            if nonNull.count != 1 {
                throw unsupportedSchemaKeywordError("type", path: path)
            }
        }

        // `additionalProperties: false` matches the closed-world native
        // generation (only declared properties are produced); `true` or a
        // schema value would require dynamic keys that DynamicGenerationSchema
        // cannot express.
        if let additional = schema["additionalProperties"], (additional as? Bool) != false {
            throw unsupportedSchemaKeywordError("additionalProperties", path: path)
        }
    }

    private func unsupportedSchemaKeywordError(_ keyword: String, path: String) -> JsonRpcError {
        JsonRpcError.unsupported(
            "JSON Schema keyword '\(keyword)' at \(path) is not supported by native guided generation.",
            data: ["code": "UNSUPPORTED_SCHEMA_TYPE", "keyword": keyword, "path": path]
        )
    }

    @available(macOS 26.0, *)
    private final class SchemaContext {
        let rootSchema: [String: Any]
        private unowned let runtime: FoundationModelsCore
        private var dependencyMap: [String: DynamicGenerationSchema] = [:]
        private var resolving: Set<String> = []

        var dependencies: [DynamicGenerationSchema] {
            dependencyMap.keys.sorted().compactMap { dependencyMap[$0] }
        }

        public init(rootSchema: [String: Any], runtime: FoundationModelsCore) {
            self.rootSchema = rootSchema
            self.runtime = runtime
        }

        func resolveReference(_ ref: String, path: String) throws -> DynamicGenerationSchema {
            guard ref.hasPrefix("#/") else {
                throw JsonRpcError.unsupported(
                    "JSON Schema '$ref' at \(path) must reference a definition within the same document.",
                    data: ["code": "UNSUPPORTED_SCHEMA_TYPE", "keyword": "$ref", "path": path]
                )
            }

            let components = ref.dropFirst(2).split(separator: "/").map(String.init)
            guard components.count >= 2,
                  components[0] == "$defs" || components[0] == "definitions" else {
                throw JsonRpcError.unsupported(
                    "JSON Schema '$ref' at \(path) must point to #/$defs/<name> or #/definitions/<name>.",
                    data: ["code": "UNSUPPORTED_SCHEMA_TYPE", "keyword": "$ref", "path": path]
                )
            }

            let defGroup = components[0]
            let defName = components[1]
            let dependencyPath = "#/\(defGroup)/\(defName)"

            if resolving.contains(defName) {
                throw JsonRpcError.unsupported(
                    "JSON Schema '$ref' at \(path) forms a circular reference to \(dependencyPath).",
                    data: ["code": "UNSUPPORTED_SCHEMA_TYPE", "keyword": "$ref", "path": path]
                )
            }

            if dependencyMap[defName] != nil {
                return DynamicGenerationSchema(referenceTo: defName)
            }

            let defs = JSON.object(rootSchema, key: defGroup) ?? [:]
            guard let defSchema = defs[defName] as? [String: Any] else {
                throw JsonRpcError.unsupported(
                    "JSON Schema '$ref' at \(path) points to an undefined definition \(dependencyPath).",
                    data: ["code": "UNSUPPORTED_SCHEMA_TYPE", "keyword": "$ref", "path": path]
                )
            }

            resolving.insert(defName)
            defer { resolving.remove(defName) }

            let resolved = try runtime.dynamicGenerationSchema(
                from: defSchema,
                name: defName,
                path: dependencyPath,
                context: self
            )
            dependencyMap[defName] = resolved
            return DynamicGenerationSchema(referenceTo: defName)
        }
    }

    @available(macOS 26.0, *)
    private func generationSchema(from rawSchema: Any?) throws -> GenerationSchema {
        guard let schemaObject = rawSchema as? [String: Any] else {
            throw JsonRpcError.invalidRequest("responseFormat.schema must be a JSON Schema object.")
        }

        let context = SchemaContext(rootSchema: schemaObject, runtime: self)
        let root = try dynamicGenerationSchema(from: schemaObject, name: "Root", path: "#", context: context)
        return try GenerationSchema(root: root, dependencies: context.dependencies)
    }

    @available(macOS 26.0, *)
    private func dynamicGenerationSchema(
        from schema: [String: Any],
        name: String,
        path: String,
        context: SchemaContext
    ) throws -> DynamicGenerationSchema {
        try ensureSupportedSchemaKeywords(schema, path: path)

        if let ref = JSON.string(schema, key: "$ref") {
            return try context.resolveReference(ref, path: path)
        }

        if let anyOf = schema["anyOf"] as? [Any] {
            let choices = try anyOf.enumerated().map { index, item -> DynamicGenerationSchema in
                guard let itemSchema = item as? [String: Any] else {
                    throw JsonRpcError.invalidRequest("anyOf entry at \(path)/anyOf/\(index) must be a JSON Schema object.")
                }
                return try dynamicGenerationSchema(
                    from: itemSchema,
                    name: "\(name)Choice\(index)",
                    path: "\(path)/anyOf/\(index)",
                    context: context
                )
            }
            guard !choices.isEmpty else {
                throw unsupportedSchemaKeywordError("anyOf", path: path)
            }
            return DynamicGenerationSchema(name: schemaName(name), anyOf: choices)
        }

        // TCK-0233 / DES-0083 / FND-0145: map nullable type arrays to the
        // native per-value union `anyOf: [T, .null]`. Evidence from the
        // installed SDK swiftinterface: `DynamicGenerationSchema.null` is a
        // free `static var` (macOS 26.4+, L2610), not object-scoped; and
        // `init(name:description:anyOf choices: [DynamicGenerationSchema])`
        // (L2617) accepts it. Intercept BEFORE enum / properties / type so
        // `type: ["string","null"]` + `enum`, or `type: ["object","null"]` +
        // `properties`, cannot fall through to a non-null mapping (silent
        // narrowing of the null branch).
        if let types = schema["type"] as? [String], types.contains("null") {
            return try nullableDynamicGenerationSchema(
                from: schema,
                types: types,
                name: name,
                path: path,
                context: context
            )
        }

        if schema["enum"] != nil {
            guard let choices = schema["enum"] as? [String], !choices.isEmpty else {
                throw JsonRpcError.unsupported(
                    "JSON Schema keyword 'enum' at \(path) is only supported as a non-empty array of strings.",
                    data: ["code": "UNSUPPORTED_SCHEMA_TYPE", "keyword": "enum", "path": path]
                )
            }
            return DynamicGenerationSchema(name: schemaName(name), anyOf: choices)
        }

        if let properties = schema["properties"] as? [String: Any] {
            return try objectGenerationSchema(schema: schema, name: name, properties: properties, path: path, context: context)
        }

        switch jsonSchemaType(schema) {
        case "object":
            return try objectGenerationSchema(schema: schema, name: name, properties: [:], path: path, context: context)
        case "array":
            let itemSchema = (schema["items"] as? [String: Any]) ?? ["type": "string"]
            return try DynamicGenerationSchema(
                arrayOf: dynamicGenerationSchema(from: itemSchema, name: "\(name)Item", path: "\(path)/items", context: context),
                minimumElements: JSON.int(schema, key: "minItems"),
                maximumElements: JSON.int(schema, key: "maxItems")
            )
        case "string":
            return try stringGenerationSchema(schema: schema, name: name, path: path)
        case "integer":
            return try integerGenerationSchema(schema: schema, name: name, path: path)
        case "number":
            return try numberGenerationSchema(schema: schema, name: name, path: path)
        case "boolean":
            return DynamicGenerationSchema(type: Bool.self)
        case "null":
            // Building block for explicit `anyOf: [{type:"string"},{type:"null"}]`
            // (same SDK surface as the type-array mapping above).
            if #available(macOS 26.4, *) {
                return DynamicGenerationSchema.null
            }
            throw JsonRpcError.unsupported(
                "Unsupported JSON Schema type for native structured output.",
                data: ["code": "UNSUPPORTED_SCHEMA_TYPE", "type": "null", "path": path]
            )
        default:
            throw JsonRpcError.unsupported(
                "Unsupported JSON Schema type for native structured output.",
                data: ["code": "UNSUPPORTED_SCHEMA_TYPE", "type": jsonSchemaType(schema) ?? "missing", "path": path]
            )
        }
    }

    /// Maps `type: ["T", "null"]` (exactly one non-null member) to
    /// `DynamicGenerationSchema(anyOf: [T, .null])` when the SDK exposes
    /// `.null` (macOS 26.4+). Rejects every other shape by name — never peels
    /// `"null"` off and returns a bare `T` schema (FND-0145 regression).
    @available(macOS 26.0, *)
    private func nullableDynamicGenerationSchema(
        from schema: [String: Any],
        types: [String],
        name: String,
        path: String,
        context: SchemaContext
    ) throws -> DynamicGenerationSchema {
        let nonNullTypes = Array(Set(types.filter { $0 != "null" }))
        guard nonNullTypes.count == 1, let soleType = nonNullTypes.first else {
            throw unsupportedSchemaKeywordError("type", path: path)
        }

        guard #available(macOS 26.4, *) else {
            // `.null` lands in macOS 26.4 (swiftinterface L2608–2610). Below
            // that gate there is no native per-value nullable union, so keep
            // the typed reject rather than guessing with object-scoped
            // `representNilExplicitlyInGeneratedContent`.
            throw unsupportedSchemaKeywordError("type", path: path)
        }

        var nonNullSchema = schema
        nonNullSchema["type"] = soleType
        let base = try dynamicGenerationSchema(
            from: nonNullSchema,
            name: name,
            path: path,
            context: context
        )
        return DynamicGenerationSchema(name: schemaName(name), anyOf: [base, .null])
    }

    @available(macOS 26.0, *)
    private func stringGenerationSchema(
        schema: [String: Any],
        name: String,
        path: String
    ) throws -> DynamicGenerationSchema {
        // FND-0146: `const` on a string schema maps onto Apple's real
        // `GenerationGuide<String>.constant` guide (SDK 27 swiftinterface
        // L1121). `ensureSupportedSchemaKeywords` already guarantees
        // `schema["const"]` is a `String` before `dynamicGenerationSchema`
        // ever dispatches into this function, so this cast cannot fail.
        if let constant = schema["const"] as? String {
            // VER-20260801-190000 (FND-0218): `const` used to win outright and
            // `pattern` was dropped without a word — the exact "silently
            // dropped" failure this ticket's own doc says never happens. The
            // two are not composable here: `DynamicGenerationSchema(type:
            // guides:)` takes both guides, but a value satisfying `.constant`
            // either already matches the pattern (the pattern is redundant) or
            // cannot (the schema is unsatisfiable), and neither reading is safe
            // to guess on the caller's behalf. Rejecting names the conflict.
            if JSON.string(schema, key: "pattern") != nil {
                throw unsupportedSchemaKeywordError("const+pattern", path: path)
            }
            return DynamicGenerationSchema(type: String.self, guides: [GenerationGuide<String>.constant(constant)])
        }

        guard let pattern = JSON.string(schema, key: "pattern") else {
            return DynamicGenerationSchema(type: String.self)
        }

        do {
            let regex = try Regex(pattern)
            return DynamicGenerationSchema(type: String.self, guides: [GenerationGuide<String>.pattern(regex)])
        } catch {
            throw unsupportedSchemaKeywordError("pattern", path: path)
        }
    }

    @available(macOS 26.0, *)
    private func integerGenerationSchema(
        schema: [String: Any],
        name: String,
        path: String
    ) throws -> DynamicGenerationSchema {
        var guides: [GenerationGuide<Int>] = []
        if let minimum = JSON.int(schema, key: "minimum") {
            guides.append(.minimum(minimum))
        }
        if let maximum = JSON.int(schema, key: "maximum") {
            guides.append(.maximum(maximum))
        }
        return DynamicGenerationSchema(type: Int.self, guides: guides)
    }

    @available(macOS 26.0, *)
    private func numberGenerationSchema(
        schema: [String: Any],
        name: String,
        path: String
    ) throws -> DynamicGenerationSchema {
        var guides: [GenerationGuide<Double>] = []
        if let minimum = JSON.double(schema, key: "minimum") {
            guides.append(.minimum(minimum))
        }
        if let maximum = JSON.double(schema, key: "maximum") {
            guides.append(.maximum(maximum))
        }
        return DynamicGenerationSchema(type: Double.self, guides: guides)
    }

    @available(macOS 26.0, *)
    private func objectGenerationSchema(
        schema: [String: Any],
        name: String,
        properties: [String: Any],
        path: String,
        context: SchemaContext
    ) throws -> DynamicGenerationSchema {
        let required = Set((schema["required"] as? [String]) ?? [])
        let dynamicProperties = try properties.keys.sorted().map { propertyName in
            guard let propertySchema = properties[propertyName] as? [String: Any] else {
                throw JsonRpcError.invalidRequest("JSON Schema property '\(propertyName)' must be an object.")
            }

            return try DynamicGenerationSchema.Property(
                name: propertyName,
                description: JSON.string(propertySchema, key: "description"),
                schema: dynamicGenerationSchema(
                    from: propertySchema,
                    name: "\(name)\(propertyName.capitalized)",
                    path: "\(path)/properties/\(propertyName)",
                    context: context
                ),
                isOptional: !required.contains(propertyName)
            )
        }

        return DynamicGenerationSchema(
            name: schemaName(name),
            description: JSON.string(schema, key: "description"),
            properties: dynamicProperties
        )
    }

    private func jsonSchemaType(_ schema: [String: Any]) -> String? {
        if let type = schema["type"] as? String {
            return type
        }

        if let types = schema["type"] as? [String] {
            return types.first { $0 != "null" } ?? types.first
        }

        return nil
    }

    private func schemaName(_ raw: String) -> String {
        let allowed = raw.filter { $0.isLetter || $0.isNumber }
        return allowed.isEmpty ? "Schema" : allowed
    }

    @available(macOS 26.0, *)
    private func jsonObject(fromGeneratedContent content: GeneratedContent) throws -> Any {
        let data = Data(content.jsonString.utf8)
        return try JSONSerialization.jsonObject(with: data)
    }
    #endif

    /// Cumulative snapshot → incremental delta (TCK-0257 / FND-0239).
    /// Delegates to UTF-8 `StreamingDelta` — avoids Character-view `count`/`hasPrefix`/`dropFirst`.
    private func textDelta(previous: String, next: String) -> String {
        StreamingDelta.textDelta(previous: previous, next: next)
    }

    private func systemModelStatus() -> (available: Bool, reason: String?, reasonCode: String?) {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return (true, nil, nil)
            case .unavailable(let reason):
                return (false, String(describing: reason), unavailableReasonCode(reason))
            @unknown default:
                return (false, "unknown", "unknown")
            }
        }
        #endif

        return (
            false,
            "foundationModelsFrameworkUnavailable",
            "foundation_models_framework_unavailable"
        )
    }

    private func pccModelStatus() -> (
        available: Bool,
        reason: String?,
        reasonCode: String?,
        quota: [String: Any]?,
        capabilities: [String: Bool]?
    ) {
        #if canImport(FoundationModels)
        if #available(macOS 27.0, *) {
            let model = PrivateCloudComputeLanguageModel()
            let quota = model.isAvailable ? pccQuotaDict(model.quotaUsage) : nil
            // Measured, not asserted (TCK-0223 / FND-0155). Constructing the model
            // is safe without the entitlement — the entitlement guard lives on the
            // inference path (`pccLanguageModel()`), not here — so the real
            // capability set is readable today.
            let caps = pccCapabilityDict(model.capabilities)
            switch model.availability {
            case .available:
                return (true, nil, nil, quota, caps)
            case .unavailable(let reason):
                return (false, String(describing: reason), pccUnavailableReasonCode(reason), nil, caps)
            @unknown default:
                return (false, "unknown", "pcc_unavailable", nil, caps)
            }
        }
        #endif

        return (
            false,
            "privateCloudComputeRequiresMacOS27",
            "pcc_unavailable",
            nil,
            nil
        )
    }

    #if canImport(FoundationModels)
    // FND-0152 (TCK-0217) — `PrivateCloudComputeLanguageModel.Availability
    // .UnavailableReason` has TWO cases (see the arm64e-apple-macos
    // .swiftinterface, `extension PrivateCloudComputeLanguageModel { public
    // enum UnavailableReason { case deviceNotEligible; case systemNotReady }
    // }` — a *different*, smaller enum than `SystemLanguageModel`'s
    // three-case `UnavailableReason` right below, and NOT the same axis as
    // `PrivateCloudComputeLanguageModel.Error` (network/quota/service, mapped
    // in `mapNativeGenerationError` where `reasonCode` deliberately STAYS
    // `"pcc_unavailable"` for every arm per TCK-0208/FND-0203 — that
    // collapse is intentional there because `pccFailureKind`/`retryable`
    // already carry the distinction for that error family).
    //
    // Before this helper, `pccModelStatus()` collapsed BOTH availability
    // cases into the single `"pcc_unavailable"` reasonCode. That erases a
    // distinction that matters operationally:
    //   - `.deviceNotEligible` is PERMANENT — this hardware/account will
    //     never see PCC; retrying is pointless.
    //   - `.systemNotReady` is TRANSIENT — the PCC subsystem has not
    //     finished initializing; the caller should wait and retry.
    // A caller that treats "wait" as "give up" (or the reverse) because both
    // collapsed to the same opaque code cannot make that call correctly.
    //
    // `internal` (no `private`), same rationale as `mlxBackendOverride` above:
    // invisible outside this package's public API, but reachable from the
    // test target via `@testable import` so the case-mapping can be pinned
    // without instantiating a real `PrivateCloudComputeLanguageModel` (which
    // needs the PCC entitlement this dev machine does not have).
    @available(macOS 27.0, *)
    func pccUnavailableReasonCode(
        _ reason: PrivateCloudComputeLanguageModel.Availability.UnavailableReason
    ) -> String {
        switch reason {
        case .deviceNotEligible:
            return "pcc_device_not_eligible"
        case .systemNotReady:
            return "pcc_system_not_ready"
        @unknown default:
            return "pcc_unavailable"
        }
    }

    /// Derives the reported `supports` flags from Apple's own capability set.
    ///
    /// Before TCK-0223 the apple.pcc block was a literal dictionary of
    /// assumptions that omitted `image` entirely — which made the TS provider
    /// reject every image sent to apple.pcc without ever asking the model
    /// whether it accepts one.
    @available(macOS 27.0, *)
    private func pccCapabilityDict(_ capabilities: LanguageModelCapabilities) -> [String: Bool] {
        [
            "image": capabilities.contains(.vision),
            "structuredOutput": capabilities.contains(.guidedGeneration),
            "reasoning": capabilities.contains(.reasoning),
            "toolCalling": capabilities.contains(.toolCalling)
        ]
    }
    #endif

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func unavailableReasonCode(
        _ reason: SystemLanguageModel.Availability.UnavailableReason
    ) -> String {
        switch reason {
        case .deviceNotEligible:
            return "device_not_eligible"
        case .appleIntelligenceNotEnabled:
            return "apple_intelligence_not_enabled"
        case .modelNotReady:
            return "model_not_ready"
        @unknown default:
            return "unknown"
        }
    }

    @available(macOS 27.0, *)
    private func pccQuotaDict(_ quota: PrivateCloudComputeLanguageModel.QuotaUsage) -> [String: Any] {
        var result: [String: Any] = [
            "isApproachingLimit": false
        ]

        switch quota.status {
        case .belowLimit(let belowLimit):
            result["status"] = "below_limit"
            result["isApproachingLimit"] = belowLimit.isApproachingLimit
        case .limitReached:
            result["status"] = "limit_reached"
            result["isApproachingLimit"] = true
        @unknown default:
            result["status"] = quota.isLimitReached ? "limit_reached" : "below_limit"
            result["isApproachingLimit"] = quota.isLimitReached
        }

        if let resetDate = quota.resetDate {
            result["resetDate"] = ISO8601DateFormatter().string(from: resetDate)
        }
        if quota.limitIncreaseSuggestion != nil {
            result["limitIncreaseSuggestion"] = true
        }

        return result
    }
    #endif

    private func estimateTokens(_ text: String) -> Int {
        max(1, text.split(whereSeparator: { $0.isWhitespace }).count)
    }

    /// Native per-request token accounting from SDK 27 `LanguageModelSession.Response.usage` /
    /// `ResponseStream.Snapshot.usage` (FND-0157, TCK-0220). `estimated:false` marks this as a
    /// real measurement, not the word-count guess in `estimatedUsageDict`. Confirmed against the
    /// installed SDK's `.swiftinterface`: `Usage.Input.totalTokenCount`/`cachedTokenCount` and
    /// `Usage.Output.totalTokenCount`/`reasoningTokenCount` (FND-0162) all exist exactly as named
    /// here — nothing in this dict is invented.
    @available(macOS 27.0, *)
    private func usageDict(from usage: LanguageModelSession.Usage) -> [String: Any] {
        [
            "inputTokens": usage.input.totalTokenCount,
            "cachedInputTokens": usage.input.cachedTokenCount,
            "outputTokens": usage.output.totalTokenCount,
            "reasoningOutputTokens": usage.output.reasoningTokenCount,
            "estimated": false
        ]
    }

    /// Word-count fallback usage (pre-27 platforms, and the MLX-/CoreAI-direct paths that bypass
    /// `LanguageModelSession` entirely and therefore never see native usage). `estimated:true`
    /// (FND-0157) so no caller mistakes this guess for a measured count — mirrors the `estimated`
    /// flag `countTokens()` already sets.
    private func estimatedUsageDict(prompt: String, outputText: String) -> [String: Any] {
        [
            "inputTokens": estimateTokens(prompt),
            "outputTokens": estimateTokens(outputText),
            "estimated": true
        ]
    }

    private func textForTokenEstimate(_ value: Any) -> String {
        if let string = value as? String {
            return string
        }

        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value),
           let string = String(data: data, encoding: .utf8) {
            return string
        }

        return String(describing: value)
    }

    private func textForToolOutput(_ value: Any) -> String {
        if let string = value as? String {
            return string
        }

        return textForTokenEstimate(value)
    }

    private func hasCallbackTools(params: [String: Any]) -> Bool {
        (JSON.array(params, key: "tools") ?? []).contains { tool in
            JSON.bool(tool, key: "callback") == true
        }
    }

    private func callbackToolNames(params: [String: Any]) -> [String] {
        (JSON.array(params, key: "tools") ?? [])
            .filter { JSON.bool($0, key: "callback") == true }
            .compactMap { JSON.string($0, key: "name") }
    }

    /// Typed policy rejection (TCK-0015c): callback tools are request-scoped to
    /// the duplex `sessions.stream` channel. `sessions.respond` and
    /// `sessions.create` reject them with the stable
    /// `TOOL_CALLBACKS_REQUIRE_STREAMING` code naming the offending tools.
    private func callbackToolsRequireStreamingError(params: [String: Any]) -> JsonRpcError {
        JsonRpcError.unsupported(
            "Callback tools are request-scoped and must be provided to sessions.stream.",
            data: [
                "code": "TOOL_CALLBACKS_REQUIRE_STREAMING",
                "tools": callbackToolNames(params: params)
            ]
        )
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
private struct BridgeTool: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let name: String
    let description: String
    let parameters: GenerationSchema
    let output: String?
    let callbackBridge: ToolCallbackBridge?
    // FND-0207 / TCK-0212: was a hardcoded `{ true }` computed property with
    // no per-tool knob; now a stored property set from the wire tool
    // definition by `nativeTools(params:toolBridge:)`, defaulting to `true`.
    let includesSchemaInInstructions: Bool

    @concurrent public func call(arguments: GeneratedContent) async throws -> String {
        if let callbackBridge {
            return try await callbackBridge.call(toolName: name, arguments: arguments)
        }

        return output ?? ""
    }
}

@available(macOS 26.0, *)
public final class ToolCallbackBridge: @unchecked Sendable {
    private let read: () async throws -> [String: Any]
    private let emit: ([String: Any]) async throws -> Void

    public init(
        read: @escaping () async throws -> [String: Any],
        emit: @escaping ([String: Any]) async throws -> Void
    ) {
        self.read = read
        self.emit = emit
    }

    public func call(toolName: String, arguments: GeneratedContent) async throws -> String {
        let toolCallId = "toolcall_swift_\(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: ""))"
        let argumentsObject = try jsonObject(fromGeneratedContent: arguments)

        // TCK-0046a — tool_call_delta: the FoundationModels SDK delivers tool call
        // arguments atomically to BridgeTool.call(arguments:); the low-level
        // LanguageModelExecutorGenerationChannel.ToolCalls.ToolCall.Action.appendArguments
        // stream is only accessible to LanguageModelExecutor *implementors*, not to
        // LanguageModelSession *consumers*.  We therefore emit a single tool_call_delta
        // carrying the complete arguments snapshot immediately before the
        // tool_call_request.  This preserves the typed contract (tool_call_delta appears
        // in the stream before tool_call_request) without introducing silence or a
        // degenerate empty delta.  If a future SDK revision exposes per-fragment
        // callbacks on the consumer side, multiple deltas can replace this single one
        // without breaking the downstream TS contract.
        //
        // TCK-0231 / FND-0178: await the inbound tool result via AsyncStream
        // (StreamInboundRouter) instead of DispatchSemaphore / queue.sync, so
        // this async call does not block a cooperative-pool thread.
        try await emit([
            "type": "tool_call_delta",
            "toolCallId": toolCallId,
            "toolName": toolName,
            "arguments": argumentsObject
        ])

        try await emit([
            "type": "tool_call_request",
            "toolCallId": toolCallId,
            "toolName": toolName,
            "arguments": argumentsObject
        ])

        let response = try await read()
        guard JSON.string(response, key: "jsonrpc") == "2.0" else {
            throw JsonRpcError.invalidRequest("Tool callback response must be a JSON-RPC 2.0 object.")
        }
        guard JSON.string(response, key: "method") == "foundationmodels.tools.result" else {
            throw JsonRpcError.invalidRequest("Expected foundationmodels.tools.result for tool callback response.")
        }

        let params = JSON.object(response, key: "params") ?? [:]
        guard JSON.string(params, key: "toolCallId") == toolCallId else {
            throw JsonRpcError.invalidRequest("Tool callback response toolCallId does not match the active call.")
        }

        // Richer error propagation (TCK-0015c): a failed TypeScript callback
        // becomes the stable -32050 TOOL_EXECUTION_FAILED contract error
        // carrying the tool name, the callback's message, and the
        // client-side callback code (TOOL_CALLBACK_ERROR /
        // TOOL_CALLBACK_NOT_FOUND).
        if let error = JSON.object(params, key: "error") {
            let reason = JSON.string(error, key: "message") ?? "TypeScript tool callback failed."
            var data: [String: Any] = [
                "code": "TOOL_EXECUTION_FAILED",
                "toolName": toolName,
                "message": reason
            ]
            if let callbackCode = JSON.string(error, key: "code") {
                data["callbackCode"] = callbackCode
            }

            throw JsonRpcError.toolExecutionFailed(
                "Tool \"\(toolName)\" failed during generation: \(reason)",
                data: data
            )
        }

        let output = params["output"] ?? NSNull()
        try await emit([
            "type": "tool_call_result",
            "toolCallId": toolCallId,
            "toolName": toolName,
            "output": output
        ])
        return textForToolOutput(output)
    }

    private func jsonObject(fromGeneratedContent content: GeneratedContent) throws -> Any {
        let data = Data(content.jsonString.utf8)
        return try JSONSerialization.jsonObject(with: data)
    }

    private func textForToolOutput(_ value: Any) -> String {
        if let string = value as? String {
            return string
        }
        if value is NSNull {
            return ""
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value),
           let string = String(data: data, encoding: .utf8) {
            return string
        }

        return String(describing: value)
    }
}
#endif
