import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 27.0, iOS 27.0, *)
public struct CoreAILanguageModel: LanguageModel {
    public typealias Executor = CoreAILanguageModelExecutor

    public let id: String
    public let registryPath: String?

    public init(id: String, registryPath: String? = nil) {
        self.id = id
        self.registryPath = registryPath
    }

    /// Capability honesty (TCK-0254 / FND-0236):
    /// - `guidedGeneration` is NOT declared: CoreAI direct-path rejects
    ///   `json_schema`, and the executor channel cannot emit guided output.
    ///   MLX structured output is served by the MLX-direct guided-decoding path,
    ///   not via this `LanguageModel` capability bit.
    /// - `toolCalling` IS declared: `sessions.create` wires tools through a real
    ///   `LanguageModelSession` (FND-0166 / TCK-0212). Direct-path respond/stream
    ///   still reject `tools` by name rather than flipping this flag.
    public var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities(capabilities: [.toolCalling])
    }

    public var executorConfiguration: CoreAILanguageModelExecutor.Configuration {
        CoreAILanguageModelExecutor.Configuration(modelId: id, registryPath: registryPath)
    }
}

@available(macOS 27.0, iOS 27.0, *)
public struct CoreAILanguageModelExecutor: LanguageModelExecutor {
    public struct Configuration: Hashable, Sendable {
        public let modelId: String
        public let registryPath: String?

        public init(modelId: String, registryPath: String? = nil) {
            self.modelId = modelId
            self.registryPath = registryPath
        }
    }

    private let configuration: Configuration

    public init(configuration: Configuration) throws {
        self.configuration = configuration
    }

    // MARK: - Backend selection

    private func selectBackend(for modelId: String) -> any InferenceBackend {
        if modelId.hasPrefix("apple.mlx:") {
            return MLXInferenceBackend()
        }
        if modelId.hasPrefix("apple.coreai:") {
            return CoreAIInferenceBackend()
        }
        // Fail-closed: unknown prefix → same error as before.
        return UnavailableInferenceBackend()
    }

    public func prewarm(model: CoreAILanguageModel, transcript: Transcript) {
        let backend = selectBackend(for: configuration.modelId)
        Task {
            await backend.prewarm(
                modelId: configuration.modelId,
                registryPath: configuration.registryPath,
                transcript: transcript
            )
        }
    }

    nonisolated(nonsending) public func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: CoreAILanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        let backend = selectBackend(for: configuration.modelId)
        try await backend.respond(
            to: request,
            modelId: configuration.modelId,
            registryPath: configuration.registryPath,
            streamingInto: channel
        )
    }
}

// MARK: - Fallback backend (fail-closed)

@available(macOS 27.0, iOS 27.0, *)
private struct UnavailableInferenceBackend: InferenceBackend {
    func prewarm(modelId: String, registryPath: String?, transcript: Transcript) async {
        // Intentionally no-op.
    }

    func generateText(
        prompt: String,
        options: GenerationOptions,
        modelId: String,
        registryPath: String?
    ) async throws -> String {
        throw JsonRpcError.modelUnavailable(
            "Core AI model \"\(modelId)\" is registered, but no inference backend is available for its prefix.",
            data: [
                "code": "INFERENCE_BACKEND_UNAVAILABLE",
                "model": modelId,
                "reasonCode": "inference_backend_unavailable"
            ]
        )
    }

    func respond(
        to request: LanguageModelExecutorGenerationRequest,
        modelId: String,
        registryPath: String?,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        throw JsonRpcError.modelUnavailable(
            "Core AI model \"\(modelId)\" is registered, but no inference backend is available for its prefix.",
            data: [
                "code": "INFERENCE_BACKEND_UNAVAILABLE",
                "model": modelId,
                "reasonCode": "inference_backend_unavailable"
            ]
        )
    }
}
#endif
