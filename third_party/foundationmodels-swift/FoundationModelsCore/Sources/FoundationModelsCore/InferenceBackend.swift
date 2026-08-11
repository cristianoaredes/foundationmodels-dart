import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Protocolo que abstrai o motor de inferência por baixo do `CoreAILanguageModelExecutor`.
/// Cada namespace (`apple.mlx:*`, `apple.coreai:*`) tem sua implementação própria.
/// O default é fail-closed (`INFERENCE_BACKEND_UNAVAILABLE`).
@available(macOS 27.0, *)
public protocol InferenceBackend: Sendable {
    func prewarm(modelId: String, registryPath: String?, transcript: Transcript) async

    /// Non-streaming text generation (ADR-0006 / DES-0051): generates the full text
    /// and returns it directly, WITHOUT going through `LanguageModelExecutorGenerationChannel`.
    /// The daemon's MLX-direct-path uses this for `apple.mlx:*` so generation is not blocked
    /// by the SDK-27-beta-sealed channel event initializers. Backends without a real engine
    /// (CoreAI tensor-wall, fail-closed default) throw `INFERENCE_BACKEND_UNAVAILABLE`.
    func generateText(
        prompt: String,
        options: GenerationOptions,
        modelId: String,
        registryPath: String?
    ) async throws -> String

    /// Streaming counterpart of `generateText` (TCK-0106 / TCK-0125): emits incremental deltas
    /// via `onDelta` and returns the full text + an estimated output-token count.
    /// `MLXInferenceBackend` and `CoreAIInferenceBackend` override this with real per-token
    /// deltas from their own decode loops; the default implementation below exists so adding
    /// this requirement stays additive for any other conformer.
    ///
    /// `isSnapshotReplace` (TCK-0121 / FND-0074): `true` only for CoreAI's rare non-prefix
    /// snapshot case, where `delta` is a full-text replacement rather than an incremental
    /// append. MLX and the default implementation never set it.
    func generateTextStream(
        prompt: String,
        options: GenerationOptions,
        modelId: String,
        registryPath: String?,
        onDelta: (_ delta: String, _ isSnapshotReplace: Bool) async throws -> Void
    ) async throws -> (text: String, outputTokenCount: Int)

    /// Vision (multimodal) counterpart of `generateText` (TCK-0109 / TCK-0125). Only the MLX
    /// backend (registry `backend: "mlx-vlm"` models) implements this today; the default below
    /// throws the same `MULTIMODAL_INPUT_UNAVAILABLE` shape the daemon already uses for
    /// non-vision models.
    func generateVisionText(
        prompt: String,
        imageData: [Data],
        options: GenerationOptions,
        modelId: String,
        registryPath: String?
    ) async throws -> String

    /// Streaming counterpart of `generateVisionText` (TCK-0111 / TCK-0125).
    func generateVisionTextStream(
        prompt: String,
        imageData: [Data],
        options: GenerationOptions,
        modelId: String,
        registryPath: String?,
        onDelta: (String) async throws -> Void
    ) async throws -> (text: String, outputTokenCount: Int)

    /// MLX guided-decoding path (TCK-0110c/d): schema-constrained generation via `TokenIterator`.
    /// Default throws `STRUCTURED_OUTPUT_UNAVAILABLE`; only `MLXInferenceBackend` (and test doubles)
    /// override with a real implementation.
    func generateStructuredText(
        prompt: String,
        options: GenerationOptions,
        schema: [String: Any],
        modelId: String,
        registryPath: String?
    ) async throws -> String

    /// Streaming variant of `generateStructuredText` (TCK-0110c/d).
    func generateStructuredTextStream(
        prompt: String,
        options: GenerationOptions,
        schema: [String: Any],
        modelId: String,
        registryPath: String?,
        onDelta: @escaping (String) async throws -> Void
    ) async throws -> (text: String, outputTokenCount: Int)

    /// Executor path (Apple-orchestrated). On MLX/CoreAI this still throws
    /// `sdk_beta_channel_event_init_unavailable` because external executors cannot emit
    /// channel events on the SDK 27 beta. Kept for the `LanguageModelExecutor` contract.
    func respond(
        to request: LanguageModelExecutorGenerationRequest,
        modelId: String,
        registryPath: String?,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws
}

/// Default implementations (TCK-0125 / FND-0088): keeps adding `generateTextStream` /
/// `generateVisionText` / `generateVisionTextStream` to the protocol additive rather than
/// source-breaking. `MLXInferenceBackend` and `CoreAIInferenceBackend` already declare their own
/// matching methods (used for real generation today), which win over these defaults via normal
/// Swift static-dispatch-to-most-specific-implementation rules — this extension only supplies a
/// safe fallback for a backend (e.g. the fail-closed default, or a test double) that only
/// implements the original 3 requirements.
@available(macOS 27.0, *)
extension InferenceBackend {
    public func generateTextStream(
        prompt: String,
        options: GenerationOptions,
        modelId: String,
        registryPath: String?,
        onDelta: (_ delta: String, _ isSnapshotReplace: Bool) async throws -> Void
    ) async throws -> (text: String, outputTokenCount: Int) {
        let text = try await generateText(prompt: prompt, options: options, modelId: modelId, registryPath: registryPath)
        if !text.isEmpty {
            try await onDelta(text, false)
        }
        return (text, max(text.count / 4, 1))
    }

    public func generateVisionText(
        prompt: String,
        imageData: [Data],
        options: GenerationOptions,
        modelId: String,
        registryPath: String?
    ) async throws -> String {
        throw JsonRpcError.modelUnavailable(
            "Multimodal input is not supported by this inference backend for model \"\(modelId)\".",
            data: [
                "code": "MULTIMODAL_INPUT_UNAVAILABLE",
                "model": modelId,
                "reasonCode": "backend_vision_unsupported"
            ]
        )
    }

    public func generateVisionTextStream(
        prompt: String,
        imageData: [Data],
        options: GenerationOptions,
        modelId: String,
        registryPath: String?,
        onDelta: (String) async throws -> Void
    ) async throws -> (text: String, outputTokenCount: Int) {
        let text = try await generateVisionText(
            prompt: prompt,
            imageData: imageData,
            options: options,
            modelId: modelId,
            registryPath: registryPath
        )
        if !text.isEmpty {
            try await onDelta(text)
        }
        return (text, max(text.count / 4, 1))
    }

    public func generateStructuredText(
        prompt: String,
        options: GenerationOptions,
        schema: [String: Any],
        modelId: String,
        registryPath: String?
    ) async throws -> String {
        throw JsonRpcError.modelUnavailable(
            "Structured output (json_schema) is not supported by this inference backend for model \"\(modelId)\".",
            data: [
                "code": "STRUCTURED_OUTPUT_UNAVAILABLE",
                "model": modelId,
                "reasonCode": "backend_structured_unsupported"
            ]
        )
    }

    public func generateStructuredTextStream(
        prompt: String,
        options: GenerationOptions,
        schema: [String: Any],
        modelId: String,
        registryPath: String?,
        onDelta: @escaping (String) async throws -> Void
    ) async throws -> (text: String, outputTokenCount: Int) {
        _ = onDelta
        throw JsonRpcError.modelUnavailable(
            "Structured output (json_schema) is not supported by this inference backend for model \"\(modelId)\".",
            data: [
                "code": "STRUCTURED_OUTPUT_UNAVAILABLE",
                "model": modelId,
                "reasonCode": "backend_structured_unsupported"
            ]
        )
    }
}
#endif
