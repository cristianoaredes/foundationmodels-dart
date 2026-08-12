import Foundation

#if canImport(FoundationModels)
import FoundationModels
#if canImport(CoreAILanguageModels)
import CoreAILanguageModels
#endif

/// Motor de inferência nativo para `apple.coreai:*` via CoreAILanguageModels
/// (runtime de alto nível da Apple sobre CoreAI.framework).
///
/// Carrega um modelo `.aimodel` do diretório `registryPath` e usa um
/// `LanguageModelSession` próprio (modelo Apple real, não o nosso executor custom)
/// para gerar texto. A direct-path (ADR-0007) devolve esse texto pelo JSON-RPC do
/// daemon, contornando o `LanguageModelExecutorGenerationChannel` lacrado da SDK 27 beta.
/// Complementa ADR-0005 (que fechou só a *tensor API* do CoreAI.framework).
///
/// TCK-0258 / FND-0240 / DES-0098: the loaded `CoreAILanguageModel` is cached in
/// `ModelHandleCache`; each request still builds a **fresh** `LanguageModelSession`
/// so transcript state never leaks across calls.
@available(macOS 27.0, iOS 27.0, *)
public struct CoreAIInferenceBackend: InferenceBackend {
    /// Process-wide handle cache (injectable for tests).
    private let cache: ModelHandleCache

    public init(cache: ModelHandleCache = .shared) {
        self.cache = cache
    }

    /// Loads the CoreAI model handle into `ModelHandleCache` (TCK-0258). Best-effort:
    /// path/attestation/framework failures are swallowed so `sessions.prewarm` stays non-throwing.
    public func prewarm(modelId: String, registryPath: String?, transcript: Transcript) async {
        _ = transcript
        do {
            _ = try await loadCachedModel(modelId: modelId, registryPath: registryPath)
        } catch {
            // Best-effort warm: leave the miss for the first real generate to surface.
        }
    }

    /// CoreAI-direct-path (ADR-0007): generates the full text via the high-level
    /// `CoreAILanguageModels` runtime and RETURNS it, bypassing the sealed channel.
    public func generateText(
        prompt: String,
        options: GenerationOptions,
        modelId: String,
        registryPath: String?
    ) async throws -> String {
        let session = try await loadSession(modelId: modelId, registryPath: registryPath)
        let response = try await session.respond(to: prompt, options: options)
        return response.content
    }

    /// Streaming variant (ADR-0007): emits cumulative-diff deltas from the Apple
    /// `LanguageModelSession.streamResponse` and returns the full text + token count.
    ///
    /// `onDelta`'s second parameter, `isSnapshotReplace` (TCK-0121 / FND-0074), is `true` only
    /// for the rare case where the model's next snapshot is NOT a strict extension of the
    /// previous one (see `computeSnapshotDelta`). Callers MUST replace their accumulated buffer
    /// with `delta` instead of appending it when `isSnapshotReplace` is `true` — silently
    /// appending the full resent snapshot (the pre-fix behavior) duplicates/corrupts the
    /// rendered text on the consumer side.
    public func generateTextStream(
        prompt: String,
        options: GenerationOptions,
        modelId: String,
        registryPath: String?,
        onDelta: (_ delta: String, _ isSnapshotReplace: Bool) async throws -> Void
    ) async throws -> (text: String, outputTokenCount: Int) {
        let session = try await loadSession(modelId: modelId, registryPath: registryPath)
        var output = ""
        let stream = session.streamResponse(to: prompt, options: options)
        for try await snapshot in stream {
            // Cooperative cancellation: stop as soon as the generation task is cancelled.
            try Task.checkCancellation()
            let next = snapshot.content
            let (delta, isSnapshotReplace) = Self.computeSnapshotDelta(previous: output, next: next)
            if !delta.isEmpty {
                try await onDelta(delta, isSnapshotReplace)
            }
            output = next
        }
        return (output, estimateTokenCount(for: output))
    }

    public func respond(
        to request: LanguageModelExecutorGenerationRequest,
        modelId: String,
        registryPath: String?,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        // Executor path: generate, then hit the channel-emit wall. The CoreAI-direct path
        // (generateText) is the supported output; this path stays gated for the executor contract.
        let session = try await loadSession(modelId: modelId, registryPath: registryPath)
        let promptText = extractPromptText(from: request.transcript)
        let response = try await session.respond(to: promptText)
        let generatedText = response.content
        let outputTokenCount = estimateTokenCount(for: generatedText)

        throw JsonRpcError.modelUnavailable(
            "CoreAI backend generated text for \"\(modelId)\", but macOS 27 SDK beta does not allow external LanguageModelExecutor implementations to emit channel events (Response/TextFragment initializers are internal). Generated \(outputTokenCount) tokens. Use the non-streaming CoreAI-direct-path (ADR-0007).",
            data: [
                "code": "INFERENCE_BACKEND_UNAVAILABLE",
                "model": modelId,
                "reasonCode": "sdk_beta_channel_event_init_unavailable",
                "generatedTextLength": generatedText.count,
                "outputTokenCount": outputTokenCount
            ]
        )
    }

    // MARK: - Helpers

    /// Fail closed before any CoreAILanguageModels symbol is touched when the
    /// weak-linked CoreAI.framework cannot satisfy the runtime (TCK-0231 / FND-0171).
    private func ensureCoreAIAvailable(modelId: String) throws {
        guard CoreAIRuntimeAvailability.isAvailable else {
            throw JsonRpcError.modelUnavailable(
                "CoreAI backend is unavailable on this system (framework symbols missing).",
                data: [
                    "code": "INFERENCE_BACKEND_UNAVAILABLE",
                    "model": modelId,
                    "reasonCode": "coreai_framework_unavailable"
                ]
            )
        }
    }

    /// Validate the registry path (existence + root allowlist), obtain a cached
    /// `CoreAILanguageModel` handle, and build a **fresh** Apple `LanguageModelSession`.
    /// Fail-closed with typed `MODEL_NOT_FOUND` on a missing/invalid path.
    ///
    /// The expensive disk load is cached (TCK-0258); the session is not, so
    /// transcript state never leaks across requests.
    private func loadSession(modelId: String, registryPath: String?) async throws -> LanguageModelSession {
        let handle = try await loadCachedModel(modelId: modelId, registryPath: registryPath)
        return LanguageModelSession(model: handle.model)
    }

    /// Path/attestation/framework gates + `ModelHandleCache.getOrLoad` for the CoreAI model
    /// (TCK-0258 / DES-0098). Shared by generate paths and real `prewarm`.
    private func loadCachedModel(
        modelId: String,
        registryPath: String?
    ) async throws -> CoreAIModelHandle {
        guard let registryPath = registryPath else {
            throw JsonRpcError.modelUnavailable(
                "CoreAI model \"\(modelId)\" requires a registryPath (local model directory with .aimodel).",
                data: [
                    "code": "MODEL_NOT_FOUND",
                    "model": modelId,
                    "reasonCode": "missing_registry_path"
                ]
            )
        }

        let modelDir = URL(fileURLWithPath: registryPath)
        guard FileManager.default.fileExists(atPath: modelDir.path) else {
            // Do not echo the operator-configured raw path back to clients (info disclosure).
            throw JsonRpcError.modelUnavailable(
                "CoreAI model directory not found for model \"\(modelId)\".",
                data: [
                    "code": "MODEL_NOT_FOUND",
                    "model": modelId,
                    "reasonCode": "model_directory_not_found"
                ]
            )
        }

        // Security (ADR-0006/0007 §7): enforce the root allowlist + traversal/symlink canonicalization,
        // the same check `availabilityModels()` reports — fail-closed for the inference path.
        if let pathIssue = CoreAIModelRegistry.validateModelPath(registryPath) {
            throw JsonRpcError.modelUnavailable(
                "CoreAI model \"\(modelId)\" path is not permitted (\(pathIssue.reason)).",
                data: [
                    "code": "MODEL_NOT_FOUND",
                    "model": modelId,
                    "reasonCode": pathIssue.reasonCode
                ]
            )
        }

        // Security (FND-0212 / TCK-0219): a declared sha256 was previously echoed
        // in availability reports but never verified anywhere — fail closed here,
        // at the same point the path allowlist above already gates the load, if
        // the registry declares a digest and the on-disk model no longer matches
        // it. No declared sha256 => nothing to verify (opt-in, unchanged behavior).
        if let registered = CoreAIModelRegistry.model(id: modelId),
           CoreAIModelRegistry.verifyAttestation(model: registered, directoryPath: registryPath) != nil {
            throw CoreAIModelRegistry.attestationError(for: modelId)
        }

        // TCK-0231 / FND-0171: probe after path/attestation gates so callers still
        // get precise MODEL_NOT_FOUND reasonCodes, but before any CoreAILanguageModels
        // entry point that would touch weak-linked symbols.
        try ensureCoreAIAvailable(modelId: modelId)

        let key = ModelHandleCache.Key(
            kind: .coreAI,
            modelId: modelId,
            registryPath: modelDir.path
        )
        return try await cache.getOrLoad(key: key, as: CoreAIModelHandle.self) {
            let coreAIModel = try await CoreAILanguageModels.CoreAILanguageModel(resourcesAt: modelDir)
            return CoreAIModelHandle(coreAIModel)
        }
    }

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

    private func estimateTokenCount(for text: String) -> Int {
        max(text.count / 4, 1)
    }

    /// Computes the next streaming chunk from a pair of cumulative snapshots (TCK-0121 /
    /// FND-0074, TCK-0257 / FND-0239). `LanguageModelSession.streamResponse` snapshots are
    /// normally monotonically-growing (`next` extends `previous`), so the common case is an
    /// incremental append. On the rare occasion the model's next snapshot is NOT a strict
    /// extension of the previous one, the full snapshot is returned as `delta` with
    /// `isSnapshotReplace: true` — silently resending it under the same incremental-delta
    /// channel (the pre-fix behavior) corrupts any consumer doing `accumulated += delta`
    /// (duplicated/garbled text).
    ///
    /// Implementation: UTF-8 `StreamingDelta` (avoids Character-view O(n) `count`/`dropFirst`
    /// per snapshot). Deliberately not `private` (default `internal` access): unit-tested
    /// directly via `@testable import` without needing a live `LanguageModelSession`.
    static func computeSnapshotDelta(previous: String, next: String) -> (delta: String, isSnapshotReplace: Bool) {
        StreamingDelta.computeSnapshotDelta(previous: previous, next: next)
    }
}

/// `@unchecked Sendable` box for a loaded `CoreAILanguageModels.CoreAILanguageModel`
/// (TCK-0258 / DES-0098). The upstream type is a struct holding non-Sendable engine
/// references; the handle is process-owned and only mutated by CoreAI internals, so
/// sharing it across the actor-isolated cache is safe. Fresh `LanguageModelSession`s
/// are built per request from `model`.
@available(macOS 27.0, iOS 27.0, *)
public final class CoreAIModelHandle: @unchecked Sendable {
    public let model: CoreAILanguageModels.CoreAILanguageModel

    public init(_ model: CoreAILanguageModels.CoreAILanguageModel) {
        self.model = model
    }
}
#endif
