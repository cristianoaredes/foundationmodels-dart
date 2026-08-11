import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Distribution-mirror stub for `apple.coreai:*` LanguageModel surface.
/// Same shape as monorepo type; CoreAIInferenceBackend is fail-closed here.
@available(macOS 27.0, *)
public struct CoreAILanguageModel: LanguageModel {
    public typealias Executor = CoreAILanguageModelExecutor

    public let id: String
    public let registryPath: String?

    public init(id: String, registryPath: String? = nil) {
        self.id = id
        self.registryPath = registryPath
    }

    public var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities(capabilities: [.toolCalling])
    }

    public var executorConfiguration: CoreAILanguageModelExecutor.Configuration {
        CoreAILanguageModelExecutor.Configuration(modelId: id, registryPath: registryPath)
    }
}

@available(macOS 27.0, *)
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

    private func selectBackend(for modelId: String) -> any InferenceBackend {
        if modelId.hasPrefix("apple.mlx:") {
            return MLXInferenceBackend()
        }
        if modelId.hasPrefix("apple.coreai:") {
            return CoreAIInferenceBackend()
        }
        return CoreAIInferenceBackend()
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
#endif
