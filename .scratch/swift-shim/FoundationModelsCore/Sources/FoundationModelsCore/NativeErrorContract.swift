import Foundation

/// Pure builders for the stable JSON-RPC contract of native Foundation Models
/// failures (TCK-0208).
///
/// Every function here takes **scalars only** — no Foundation Models SDK types.
/// That is deliberate and load-bearing for two reasons:
///
/// 1. **Privacy (R1).** The native error payloads carry an untyped
///    `metadata: [String: any Sendable]` bag, raw `[Transcript.Entry]` prompt
///    content, and the model's `rawContent`. None of that may reach the wire.
///    Because these builders cannot *see* those types, the only thing that can
///    cross the boundary is what the call site explicitly extracts: typed
///    scalars plus the native `debugDescription` (which every pre-existing arm
///    of `mapNativeGenerationError` already emits as `reason`).
/// 2. **Testability.** The suite can exercise the whole contract without
///    linking or `dlopen`-ing `FoundationModels.framework`.
///
/// The `data.code` string — not the numeric JSON-RPC code — is the contract
/// clients map to typed errors (see docs/protocol.md). The numeric code is a
/// coarse classification: `-32060` = a decision of the safety layer
/// (non-retryable), `-32070` = a transient model/session condition
/// (retryable).
///
/// The macOS 26 deprecated `LanguageModelSession.GenerationError` cases route
/// through the SAME builders as their macOS 27 `LanguageModelError`
/// replacements, so the emitted contract does not change when the host
/// upgrades its OS.
enum NativeErrorContract {

    // MARK: - LanguageModelError (macOS 27) / GenerationError (macOS 26)

    /// `LanguageModelError.contextSizeExceeded` / `exceededContextWindowSize`.
    /// `contextSize` and `tokenCount` are only available on macOS 27.
    static func contextSizeExceeded(
        contextSize: Int? = nil,
        tokenCount: Int? = nil,
        reason: String
    ) -> JsonRpcError {
        var data: [String: Any] = [
            "code": "CONTEXT_OVERFLOW",
            "reason": reason
        ]
        if let contextSize {
            data["contextSize"] = contextSize
        }
        if let tokenCount {
            data["tokenCount"] = tokenCount
        }
        return JsonRpcError.contextOverflow(
            "The request exceeded the on-device model context window.",
            data: data
        )
    }

    /// `LanguageModelError.rateLimited`. `resetDate` is serialized as ISO 8601.
    static func rateLimited(resetDate: Date? = nil, reason: String) -> JsonRpcError {
        var data: [String: Any] = [
            "code": "RATE_LIMITED",
            "reason": reason
        ]
        if let resetDate {
            data["resetDate"] = ISO8601DateFormatter().string(from: resetDate)
        }
        return JsonRpcError.transient(
            "The model is rate limiting this client.",
            data: data
        )
    }

    /// `LanguageModelError.guardrailViolation`.
    static func guardrailViolation(reason: String) -> JsonRpcError {
        JsonRpcError.policyBlocked(
            "The request or response was blocked by the model safety guardrails.",
            data: [
                "code": "GUARDRAIL_VIOLATION",
                "reason": reason
            ]
        )
    }

    /// `LanguageModelError.refusal`.
    static func refusal(reason: String) -> JsonRpcError {
        JsonRpcError.policyBlocked(
            "The model refused to answer the prompt.",
            data: [
                "code": "MODEL_REFUSAL",
                "reason": reason
            ]
        )
    }

    /// `LanguageModelError.unsupportedCapability(.vision)` — reuses the stable
    /// multimodal degradation contract already emitted by the MLX and CoreAI
    /// paths (same `data.code`, same numeric code) instead of minting a second
    /// way to say "this model cannot see images".
    static func unsupportedVisionCapability(model: String, reason: String) -> JsonRpcError {
        JsonRpcError.modelUnavailable(
            "Multimodal input is not available for model \"\(model)\".",
            data: [
                "code": "MULTIMODAL_INPUT_UNAVAILABLE",
                "model": model,
                "capability": "vision",
                "reason": reason
            ]
        )
    }

    /// `LanguageModelError.unsupportedCapability` for every capability other
    /// than `.vision`.
    static func unsupportedCapability(capability: String, reason: String) -> JsonRpcError {
        JsonRpcError.unsupported(
            "The model does not support the required capability \"\(capability)\".",
            data: [
                "code": "UNSUPPORTED_OPERATION",
                "capability": capability,
                "reason": reason
            ]
        )
    }

    /// `LanguageModelError.unsupportedTranscriptContent`. Only the *count* of
    /// rejected entries crosses the wire — the entries themselves are raw
    /// prompt content (R1).
    static func unsupportedTranscriptContent(entryCount: Int, reason: String) -> JsonRpcError {
        JsonRpcError.unsupported(
            "The session transcript contains content this model cannot consume.",
            data: [
                "code": "UNSUPPORTED_TRANSCRIPT_CONTENT",
                "entryCount": entryCount,
                "reason": reason
            ]
        )
    }

    /// `LanguageModelError.unsupportedGenerationGuide` / `unsupportedGuide`.
    static func unsupportedGenerationGuide(schemaName: String? = nil, reason: String) -> JsonRpcError {
        var data: [String: Any] = [
            "code": "UNSUPPORTED_GENERATION_GUIDE",
            "reason": reason
        ]
        if let schemaName {
            data["schemaName"] = schemaName
        }
        return JsonRpcError.unsupported(
            "The model cannot honor the requested generation guide.",
            data: data
        )
    }

    /// `LanguageModelError.unsupportedLanguageOrLocale`.
    static func unsupportedLanguageOrLocale(languageCode: String? = nil, reason: String) -> JsonRpcError {
        var data: [String: Any] = [
            "code": "UNSUPPORTED_LANGUAGE_OR_LOCALE",
            "reason": reason
        ]
        if let languageCode {
            data["languageCode"] = languageCode
        }
        return JsonRpcError.unsupported(
            "The model does not support the language or locale of the request.",
            data: data
        )
    }

    /// `LanguageModelError.timeout`. Reuses the already-published
    /// `MODEL_TIMEOUT` contract code, which until TCK-0208 was declared by the
    /// TypeScript union but never produced by the daemon.
    static func timeout(reason: String) -> JsonRpcError {
        JsonRpcError.transient(
            "The model timed out before completing the request.",
            data: [
                "code": "MODEL_TIMEOUT",
                "reason": reason
            ]
        )
    }

    /// A `LanguageModelError` case added by a future SDK. Emitted as a plain
    /// internal error *with* a `data.code`, so clients get a contract instead
    /// of a bare `-32603`.
    static func unknownModelError(reason: String) -> JsonRpcError {
        JsonRpcError.internalError(
            "The model failed with an error this daemon build does not recognize.",
            data: [
                "code": "UNKNOWN_MODEL_ERROR",
                "reason": reason
            ]
        )
    }

    // MARK: - LanguageModelSession.Error (macOS 27) — FND-0159

    /// `LanguageModelSession.Error.concurrentRequests`.
    static func sessionBusy(reason: String) -> JsonRpcError {
        JsonRpcError.transient(
            "The session is already serving another request.",
            data: [
                "code": "SESSION_BUSY",
                "reason": reason
            ]
        )
    }

    /// `LanguageModelSession.Error.transcriptMutationWhileResponding`.
    static func transcriptMutationWhileResponding(reason: String) -> JsonRpcError {
        JsonRpcError.transient(
            "The session transcript was mutated while the model was responding.",
            data: [
                "code": "TRANSCRIPT_MUTATION_WHILE_RESPONDING",
                "reason": reason
            ]
        )
    }

    // MARK: - Guided generation — FND-0144

    /// `GenerationSchema.SchemaError` (all four cases). Reuses the stable
    /// `UNSUPPORTED_SCHEMA_TYPE` contract already emitted by the daemon's own
    /// JSON-Schema bridge; `schemaErrorCase` disambiguates which native case
    /// fired.
    static func schemaError(
        schemaErrorCase: String,
        schema: String? = nil,
        property: String? = nil,
        references: [String]? = nil,
        reason: String
    ) -> JsonRpcError {
        var data: [String: Any] = [
            "code": "UNSUPPORTED_SCHEMA_TYPE",
            "schemaErrorCase": schemaErrorCase,
            "reason": reason
        ]
        if let schema {
            data["schema"] = schema
        }
        if let property {
            data["property"] = property
        }
        if let references {
            data["references"] = references
        }
        return JsonRpcError.unsupported(
            "The generation schema was rejected by the model: \(schemaErrorCase).",
            data: data
        )
    }

    /// `GeneratedContent.ParsingError`. The model's `rawContent` is
    /// deliberately NOT forwarded (R1) — it is unvalidated model output that
    /// can echo prompt material.
    static func parsingError(reason: String) -> JsonRpcError {
        JsonRpcError.internalError(
            "The model produced output that could not be parsed against the requested schema.",
            data: [
                "code": "STRUCTURED_OUTPUT_VALIDATION_FAILED",
                "reason": reason
            ]
        )
    }

    // MARK: - Availability — FND-0203

    /// `SystemLanguageModel.Error.assetsUnavailable` — the macOS 27 replacement
    /// for the deprecated `GenerationError.assetsUnavailable`. Reuses the
    /// stable availability contract (`APPLE_MODEL_UNAVAILABLE` /
    /// `model_not_ready`) that the daemon's `availability` report already
    /// emits for the same condition.
    static func assetsUnavailable(reason: String) -> JsonRpcError {
        JsonRpcError.modelUnavailable(
            "The Apple on-device model assets are not ready.",
            data: [
                "code": "APPLE_MODEL_UNAVAILABLE",
                "reason": reason,
                "reasonCode": "model_not_ready"
            ]
        )
    }
}
