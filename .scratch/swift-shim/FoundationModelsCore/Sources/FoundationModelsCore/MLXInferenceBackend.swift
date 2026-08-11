import Foundation

#if canImport(FoundationModels)
import CoreImage
import FoundationModels
import MLX
import MLXLLM
import MLXVLM
import MLXLMCommon
import Tokenizers

/// Motor de inferência para `apple.mlx:*` via mlx-swift + swift-transformers.
/// Carrega modelo MLX do disco (registryPath), tokeniza via swift-transformers,
/// roda generate loop com sampling e emite deltas no channel.
///
/// TCK-0258 / FND-0240 / DES-0098: model containers are obtained through
/// `ModelHandleCache` so repeated requests (and `prewarm`) reuse the resident
/// handle instead of reloading weights from disk every call.
///
/// ⚠️ Bloqueio SDK 27 beta: `LanguageModelExecutorGenerationChannel` event types
/// (`Response`, `TextFragment`, etc.) não expõem initializers públicos, impedindo
/// implementadores externos de emitir deltas no channel. A lógica de geração está
/// implementada; a emissão será habilitada quando o SDK expuser os inits públicos.
@available(macOS 27.0, *)
public struct MLXInferenceBackend: InferenceBackend {
    /// Process-wide handle cache (injectable for tests).
    private let cache: ModelHandleCache

    public init(cache: ModelHandleCache = .shared) {
        self.cache = cache
    }

    /// Loads the LLM container into `ModelHandleCache` (TCK-0258). Best-effort:
    /// path/attestation failures are swallowed so `sessions.prewarm` stays non-throwing.
    public func prewarm(modelId: String, registryPath: String?, transcript: Transcript) async {
        _ = transcript
        do {
            _ = try await loadMLXContainer(kind: .mlxLLM, modelId: modelId, registryPath: registryPath)
        } catch {
            // Best-effort warm: leave the miss for the first real generate to surface.
        }
    }

    /// MLX-direct-path (ADR-0006 / DES-0051): runs the full generation and RETURNS the text,
    /// bypassing the SDK-27-beta-sealed channel. The daemon calls this for `apple.mlx:*`.
    public func generateText(
        prompt: String,
        options: GenerationOptions,
        modelId: String,
        registryPath: String?
    ) async throws -> String {
        let result = try await runGeneration(
            prompt: prompt,
            options: options,
            modelId: modelId,
            registryPath: registryPath
        )
        return result.text
    }

    /// Streaming variant of the MLX-direct-path (TCK-0106): emits each decoded chunk via `onDelta`
    /// (real deltas from the mlx-swift-lm loop) and returns the full text + token count for the
    /// terminal result frame. Bypasses `LanguageModelExecutorGenerationChannel` like `generateText`.
    public func generateTextStream(
        prompt: String,
        options: GenerationOptions,
        modelId: String,
        registryPath: String?,
        onDelta: (_ delta: String, _ isSnapshotReplace: Bool) async throws -> Void
    ) async throws -> (text: String, outputTokenCount: Int) {
        // MLX's decode loop only ever emits true incremental chunks (TCK-0121 confirmed this is
        // isolated to CoreAI) — always report isSnapshotReplace: false.
        try await runGeneration(
            prompt: prompt,
            options: options,
            modelId: modelId,
            registryPath: registryPath,
            onDelta: { delta in try await onDelta(delta, false) }
        )
    }

    /// MLX guided-decoding path (TCK-0110c): drives `TokenIterator` with `JSONSchemaLogitProcessor`
    /// instead of the high-level `generate` API (no custom processor surface).
    public func generateStructuredText(
        prompt: String,
        options: GenerationOptions,
        schema: [String: Any],
        modelId: String,
        registryPath: String?
    ) async throws -> String {
        let result = try await runGuidedGeneration(
            prompt: prompt,
            options: options,
            schema: schema,
            modelId: modelId,
            registryPath: registryPath
        )
        return result.text
    }

    /// Streaming variant of the MLX guided-decoding path (TCK-0110c).
    public func generateStructuredTextStream(
        prompt: String,
        options: GenerationOptions,
        schema: [String: Any],
        modelId: String,
        registryPath: String?,
        onDelta: @escaping (String) async throws -> Void
    ) async throws -> (text: String, outputTokenCount: Int) {
        try await runGuidedGeneration(
            prompt: prompt,
            options: options,
            schema: schema,
            modelId: modelId,
            registryPath: registryPath,
            onDelta: onDelta
        )
    }

    /// Vision (multimodal) generation for VLM models (TCK-0109): loads the model via
    /// `VLMModelFactory`, attaches the decoded images to `UserInput`, and returns the generated
    /// text. The model's `UserInputProcessor` handles resize/normalize/`<image>`-token injection.
    public func generateVisionText(
        prompt: String,
        imageData: [Data],
        options: GenerationOptions,
        modelId: String,
        registryPath: String?
    ) async throws -> String {
        try await runVisionGeneration(
            prompt: prompt, imageData: imageData, options: options,
            modelId: modelId, registryPath: registryPath
        ).text
    }

    /// Streaming variant of the VLM path (TCK-0111): emits each decoded chunk via `onDelta` and
    /// returns the full text + token count. Bypasses the channel like the text streaming path.
    public func generateVisionTextStream(
        prompt: String,
        imageData: [Data],
        options: GenerationOptions,
        modelId: String,
        registryPath: String?,
        onDelta: (String) async throws -> Void
    ) async throws -> (text: String, outputTokenCount: Int) {
        try await runVisionGeneration(
            prompt: prompt, imageData: imageData, options: options,
            modelId: modelId, registryPath: registryPath, onDelta: onDelta
        )
    }

    /// Shared VLM generation core: validate path → load via `VLMModelFactory` → decode images →
    /// `UserInput` (with the `images` populate fix) → `prepare` → generate loop (optional `onDelta`).
    private func runVisionGeneration(
        prompt: String,
        imageData: [Data],
        options: GenerationOptions,
        modelId: String,
        registryPath: String?,
        onDelta: (String) async throws -> Void = { _ in }
    ) async throws -> (text: String, outputTokenCount: Int) {
        guard let registryPath = registryPath else {
            throw JsonRpcError.modelUnavailable(
                "MLX model \"\(modelId)\" requires a registryPath (local model directory).",
                data: ["code": "MODEL_NOT_FOUND", "model": modelId, "reasonCode": "missing_registry_path"]
            )
        }
        let modelDir = URL(fileURLWithPath: registryPath)
        guard FileManager.default.fileExists(atPath: modelDir.path) else {
            throw JsonRpcError.modelUnavailable(
                "MLX model directory not found for model \"\(modelId)\".",
                data: ["code": "MODEL_NOT_FOUND", "model": modelId, "reasonCode": "model_directory_not_found"]
            )
        }
        // Security (ADR-0006 §7): enforce the model-root allowlist on the vision path too.
        if let pathIssue = CoreAIModelRegistry.validateModelPath(registryPath) {
            throw JsonRpcError.modelUnavailable(
                "MLX model \"\(modelId)\" path is not permitted (\(pathIssue.reason)).",
                data: ["code": "MODEL_NOT_FOUND", "model": modelId, "reasonCode": pathIssue.reasonCode]
            )
        }
        // Security (FND-0212 / TCK-0219): fail closed on a declared-but-mismatched
        // sha256 on the vision path too — see CoreAIModelRegistry.verifyAttestation.
        if let registered = CoreAIModelRegistry.model(id: modelId),
           CoreAIModelRegistry.verifyAttestation(model: registered, directoryPath: registryPath) != nil {
            throw CoreAIModelRegistry.attestationError(for: modelId)
        }

        // TCK-0226 / FND-0150: `CIImage(data:)` ignores the EXIF orientation tag
        // unless asked — CIImage.h is explicit that the default behaves as if
        // `applyOrientationProperty: false` had been passed — so a rotated photo
        // reached the VLM sideways. Unlike the Attachment path, which forwards the
        // orientation as metadata for the model to apply, this bakes the rotation
        // into the pixels (and clears the tag), which is what MLX needs.
        let images: [UserInput.Image] = imageData.compactMap { data in
            CIImage(data: data, options: [.applyOrientationProperty: true])
                .map { UserInput.Image.ciImage($0) }
        }
        guard !images.isEmpty else {
            throw JsonRpcError.modelUnavailable(
                "MLX vision model \"\(modelId)\" requires at least one decodable image.",
                data: ["code": "MULTIMODAL_INPUT_UNAVAILABLE", "model": modelId, "reasonCode": "mlx_image_undecodable"]
            )
        }

        // Path/attestation already validated above; load via cache (TCK-0258).
        let modelContainer = try await loadMLXContainer(
            kind: .mlxVLM,
            modelId: modelId,
            registryPath: registryPath
        )

        var userInput = UserInput(prompt: prompt, images: images)
        // `UserInput(prompt:images:)` stores the images inside the chat message, but Swift does NOT
        // fire the `prompt` `didSet` (which rebuilds `images` from the messages) during `init` — so
        // `userInput.images` stays empty and the VLM processor (which reads `input.images`,
        // Qwen2VL.swift) takes the text-only path and drops the image. Populate it explicitly.
        userInput.images = images
        let lmInput = try await modelContainer.prepare(input: userInput)
        let params = mapGenerationOptions(options)
        let stream = try await modelContainer.generate(input: lmInput, parameters: params)

        var generatedText = ""
        var outputTokenCount = 0
        for await event in stream {
            try Task.checkCancellation()
            switch event {
            case .chunk(let text):
                generatedText += text
                outputTokenCount += estimateTokenCount(for: text)
                try await onDelta(text)
            case .info(let info):
                _ = info
            case .toolCall:
                break
            }
        }
        return (generatedText, outputTokenCount)
    }

    public func respond(
        to request: LanguageModelExecutorGenerationRequest,
        modelId: String,
        registryPath: String?,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        // Executor path: generate, then hit the channel-emit wall. The generation logic is
        // shared with `generateText` via `runGeneration`; only the sink differs. Kept so the
        // `LanguageModelExecutor` contract and its tests stay intact.
        let promptText = extractPromptText(from: request.transcript)
        let result = try await runGeneration(
            prompt: promptText,
            options: request.generationOptions,
            modelId: modelId,
            registryPath: registryPath
        )

        // Bloqueio: SDK 27 beta não permite construir eventos do channel.
        // O texto FOI gerado acima (`result`), mas não podemos emiti-lo no channel.
        // O MLX-direct-path (generateText) é a saída suportada; este path permanece gated.
        throw JsonRpcError.modelUnavailable(
            "MLX backend generated text for \"\(modelId)\", but macOS 27 SDK beta does not allow external LanguageModelExecutor implementations to emit channel events (Response/TextFragment initializers are internal). Generated \(result.outputTokenCount) tokens. Use the non-streaming MLX-direct-path (ADR-0006).",
            data: [
                "code": "INFERENCE_BACKEND_UNAVAILABLE",
                "model": modelId,
                "reasonCode": "sdk_beta_channel_event_init_unavailable",
                "generatedTextLength": result.text.count,
                "outputTokenCount": result.outputTokenCount
            ]
        )
    }

    /// Shared generation core: validate path → load model+tokenizer → tokenize prompt →
    /// run the mlx-swift-lm decode loop with sampling → accumulate and return the text.
    /// Fail-closed on a missing/invalid registry path with a typed `MODEL_NOT_FOUND`.
    private func runGuidedGeneration(
        prompt: String,
        options: GenerationOptions,
        schema: [String: Any],
        modelId: String,
        registryPath: String?,
        onDelta: @escaping (String) async throws -> Void = { _ in }
    ) async throws -> (text: String, outputTokenCount: Int) {
        let modelDir = try resolveMLXModelDirectory(modelId: modelId, registryPath: registryPath)
        let modelContainer = try await loadMLXContainer(
            kind: .mlxLLM,
            modelId: modelId,
            registryPath: registryPath
        )

        let userInput = UserInput(prompt: prompt)
        let lmInput = try await modelContainer.prepare(input: userInput)
        let params = mapGenerationOptions(options)

        let inputs = GuidedGenerationInputs(
            lmInput: lmInput,
            schema: schema,
            params: params,
            modelDirectory: modelDir,
            deltaHandler: GuidedDeltaHandlerBox(onDelta)
        )

        return try await modelContainer.perform(nonSendable: inputs) { context, inputs in
            let schemaProcessor = try JSONSchemaLogitProcessor(
                schema: inputs.schema,
                vocabulary: MLXTokenizerVocabulary(
                    tokenizer: context.tokenizer,
                    modelDirectory: inputs.modelDirectory
                )
            )
            let processor: any LogitProcessor = ComposingLogitProcessor(
                first: inputs.params.processor(),
                second: schemaProcessor
            )

            var iterator = try TokenIterator(
                input: inputs.lmInput,
                model: context.model,
                processor: processor,
                sampler: inputs.params.sampler(),
                prefillStepSize: inputs.params.prefillStepSize,
                maxTokens: inputs.params.maxTokens
            )

            var stopTokenIds = context.configuration.eosTokenIds
            if let eosTokenId = context.tokenizer.eosTokenId {
                stopTokenIds.insert(eosTokenId)
            }
            for token in context.configuration.extraEOSTokens {
                if let id = context.tokenizer.convertTokenToId(token) {
                    stopTokenIds.insert(id)
                }
            }

            var generatedTokenIds = [Int]()
            var detokenizer = NaiveStreamingDetokenizer(tokenizer: context.tokenizer)

            while let token = iterator.next() {
                try Task.checkCancellation()
                if stopTokenIds.contains(token) {
                    break
                }

                generatedTokenIds.append(token)
                detokenizer.append(token: token)
                while let delta = detokenizer.next() {
                    try await inputs.deltaHandler.handler(delta)
                }
            }

            Stream().synchronize()

            let text = context.tokenizer.decode(tokenIds: generatedTokenIds)
            return (text, generatedTokenIds.count)
        }
    }

    private func runGeneration(
        prompt: String,
        options: GenerationOptions,
        modelId: String,
        registryPath: String?,
        onDelta: (String) async throws -> Void = { _ in }
    ) async throws -> (text: String, outputTokenCount: Int) {
        // 1. Resolve path + load (or reuse) model container via cache (TCK-0258).
        _ = try resolveMLXModelDirectory(modelId: modelId, registryPath: registryPath)
        let modelContainer = try await loadMLXContainer(
            kind: .mlxLLM,
            modelId: modelId,
            registryPath: registryPath
        )

        // 2. Preparar input para o mlx-swift-lm.
        let userInput = UserInput(prompt: prompt)
        let lmInput = try await modelContainer.prepare(input: userInput)

        // 3. Mapear GenerationOptions → GenerateParameters.
        let params = mapGenerationOptions(options)

        // 4. Gerar (decode loop + sampling) e acumular o texto.
        let stream = try await modelContainer.generate(
            input: lmInput,
            parameters: params
        )

        var generatedText = ""
        var outputTokenCount = 0
        for await event in stream {
            // Cooperative cancellation: stop as soon as the generation task is cancelled
            // (e.g. a streaming client disconnected), mirroring the system stream path.
            try Task.checkCancellation()
            switch event {
            case .chunk(let text):
                generatedText += text
                outputTokenCount += estimateTokenCount(for: text)
                try await onDelta(text)
            case .info(let info):
                _ = info
            case .toolCall:
                break
            }
        }

        return (generatedText, outputTokenCount)
    }

    private func resolveMLXModelDirectory(modelId: String, registryPath: String?) throws -> URL {
        guard let registryPath = registryPath else {
            throw JsonRpcError.modelUnavailable(
                "MLX model \"\(modelId)\" requires a registryPath (local model directory).",
                data: [
                    "code": "MODEL_NOT_FOUND",
                    "model": modelId,
                    "reasonCode": "missing_registry_path"
                ]
            )
        }

        let modelDir = URL(fileURLWithPath: registryPath)
        guard FileManager.default.fileExists(atPath: modelDir.path) else {
            throw JsonRpcError.modelUnavailable(
                "MLX model directory not found for model \"\(modelId)\".",
                data: [
                    "code": "MODEL_NOT_FOUND",
                    "model": modelId,
                    "reasonCode": "model_directory_not_found"
                ]
            )
        }

        if let pathIssue = CoreAIModelRegistry.validateModelPath(registryPath) {
            throw JsonRpcError.modelUnavailable(
                "MLX model \"\(modelId)\" path is not permitted (\(pathIssue.reason)).",
                data: [
                    "code": "MODEL_NOT_FOUND",
                    "model": modelId,
                    "reasonCode": pathIssue.reasonCode
                ]
            )
        }
        // Security (FND-0212 / TCK-0219): fail closed on a declared-but-mismatched
        // sha256 — shared by both `runGeneration` and `runGuidedGeneration`, which
        // both resolve their model directory through this function.
        if let registered = CoreAIModelRegistry.model(id: modelId),
           CoreAIModelRegistry.verifyAttestation(model: registered, directoryPath: registryPath) != nil {
            throw CoreAIModelRegistry.attestationError(for: modelId)
        }

        return modelDir
    }

    /// Loads (or reuses) an MLX `ModelContainer` through `ModelHandleCache` (TCK-0258 / DES-0098).
    /// Path validation and attestation still run on every call via `resolveMLXModelDirectory`
    /// so a revoked/mismatched model fails closed even when a stale handle would otherwise hit.
    private func loadMLXContainer(
        kind: ModelHandleCache.Kind,
        modelId: String,
        registryPath: String?
    ) async throws -> ModelContainer {
        let modelDir = try resolveMLXModelDirectory(modelId: modelId, registryPath: registryPath)
        let key = ModelHandleCache.Key(kind: kind, modelId: modelId, registryPath: modelDir.path)
        return try await cache.getOrLoad(key: key, as: ModelContainer.self) {
            let tokenizerLoader = TransformersTokenizerLoader()
            switch kind {
            case .mlxVLM:
                return try await VLMModelFactory.shared.loadContainer(
                    from: modelDir,
                    using: tokenizerLoader
                )
            case .mlxLLM, .coreAI:
                return try await LLMModelFactory.shared.loadContainer(
                    from: modelDir,
                    using: tokenizerLoader
                )
            }
        }
    }

    // MARK: - Helpers

    private func extractPromptText(from transcript: Transcript) -> String {
        var parts: [String] = []
        for entry in transcript {
            switch entry {
            case .prompt(let prompt):
                for segment in prompt.segments {
                    switch segment {
                    case .text(let textSegment):
                        parts.append(textSegment.content)
                    default:
                        break
                    }
                }
            default:
                break
            }
        }
        return parts.joined(separator: "\n")
    }

    private func mapGenerationOptions(_ options: GenerationOptions) -> GenerateParameters {
        var params = GenerateParameters()
        let mirror = Mirror(reflecting: options)
        for child in mirror.children {
            switch child.label {
            case "temperature":
                if let temp = child.value as? Double {
                    params.temperature = Float(temp)
                }
            case "maximumResponseTokens":
                if let maxTokens = child.value as? Int {
                    params.maxTokens = maxTokens
                }
            case "samplingMode":
                let samplingMirror = Mirror(reflecting: child.value)
                if let enumCase = samplingMirror.children.first {
                    if enumCase.label == "topP",
                       let topPValue = enumCase.value as? Double {
                        params.topP = Float(topPValue)
                    }
                }
            default:
                break
            }
        }
        return params
    }

    private func estimateTokenCount(for text: String) -> Int {
        max(text.count / 4, 1)
    }
}

// MARK: - TokenizerLoader

@available(macOS 27.0, *)
private struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    public init() {}

    public func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await Tokenizers.AutoTokenizer.from(modelFolder: directory)
        return TokenizerBridge(upstream)
    }
}

@available(macOS 27.0, *)
private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        try upstream.applyChatTemplate(
            messages: messages,
            tools: tools,
            additionalContext: additionalContext
        )
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }
}

@available(macOS 27.0, *)
private final class GuidedDeltaHandlerBox: @unchecked Sendable {
    let handler: (String) async throws -> Void

    init(_ handler: @escaping (String) async throws -> Void) {
        self.handler = handler
    }
}

@available(macOS 27.0, *)
private struct GuidedGenerationInputs {
    let lmInput: LMInput
    let schema: [String: Any]
    let params: GenerateParameters
    let modelDirectory: URL
    let deltaHandler: GuidedDeltaHandlerBox
}

#endif
