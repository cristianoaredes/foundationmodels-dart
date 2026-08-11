import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Distribution-mirror stub: full CoreAI requires apple/coreai-models which
/// pulls xgrammar@main (unstable), breaking SPM `from:` resolution.
/// Fail closed; monorepo path keeps the real backend.
@available(macOS 27.0, *)
public struct CoreAIInferenceBackend: InferenceBackend {
    public init() {}

    public func prewarm(modelId: String, registryPath: String?, transcript: Transcript) async {}

    public func generateText(
        prompt: String,
        options: GenerationOptions,
        modelId: String,
        registryPath: String?
    ) async throws -> String {
        throw JsonRpcError.modelUnavailable(
            "CoreAI backend is not included in foundationmodels-swift distribution (SPM stable graph). Use FOUNDATIONMODELS_SWIFT_PATH monorepo for apple.coreai:*.",
            data: [
                "code": "INFERENCE_BACKEND_UNAVAILABLE",
                "backend": "coreai",
                "reasonCode": "distribution_stub",
                "model": modelId,
            ]
        )
    }

    public func respond(
        to request: LanguageModelExecutorGenerationRequest,
        modelId: String,
        registryPath: String?,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        throw JsonRpcError.modelUnavailable(
            "CoreAI backend is not included in foundationmodels-swift distribution.",
            data: [
                "code": "INFERENCE_BACKEND_UNAVAILABLE",
                "backend": "coreai",
                "model": modelId,
            ]
        )
    }
}
#endif
