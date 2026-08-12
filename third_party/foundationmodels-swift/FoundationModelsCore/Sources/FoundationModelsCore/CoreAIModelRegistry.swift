import CryptoKit
import Darwin
import Foundation

struct CoreAIRegisteredModel: Sendable {
    let id: String
    let path: String?
    let sha256: String?
    let backend: String
}

/// A registered model's declared `sha256` did not match the freshly computed
/// manifest digest of the on-disk model (FND-0212, TCK-0219).
struct ModelAttestationMismatch: Sendable {
    let expected: String
    let actual: String
}

/// TCK-0231 / FND-0171 / TCK-0254: CoreAI is weak-linked (`-weak_framework CoreAI`).
/// Probe the OS framework for the symbol that previously aborted dyld on SDK↔OS
/// skew before any `CoreAILanguageModels` entry point is touched. Shared by the
/// inference backend (fail-closed load) and `availabilityModels()` (honest
/// discovery) so a registered model is not permanently reported unavailable
/// when the framework is present, and is not reported available when it is not.
enum CoreAIRuntimeAvailability {
    static let isAvailable: Bool = {
        let path = "/System/Library/Frameworks/CoreAI.framework/Versions/A/CoreAI"
        guard let handle = dlopen(path, RTLD_LAZY | RTLD_FIRST) else {
            return false
        }
        // Missing on skewed installs (FND-0171 evidence):
        // `_$s13CoreAIRuntime17NDArrayDescriptorV5shapeSaySiGvM`
        return dlsym(handle, "$s13CoreAIRuntime17NDArrayDescriptorV5shapeSaySiGvM") != nil
    }()
}

enum CoreAIModelRegistry {
    static let modelListEnvironmentKey = "FOUNDATIONMODELS_COREAI_MODELS"
    static let modelRootsEnvironmentKey = "FOUNDATIONMODELS_COREAI_MODEL_ROOTS"

    static func isCoreAIModelId(_ modelId: String?) -> Bool {
        guard let modelId else {
            return false
        }
        return modelId.hasPrefix("apple.coreai:") || modelId.hasPrefix("apple.mlx:")
    }

    static func registeredModels() -> [CoreAIRegisteredModel] {
        guard let raw = ProcessInfo.processInfo.environment[modelListEnvironmentKey],
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = raw.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data),
              let items = value as? [[String: Any]] else {
            return []
        }

        return items.compactMap { item in
            guard let id = item["id"] as? String,
                  isSafeModelId(id),
                  isCoreAIModelId(id) else {
                return nil
            }

            let path = item["path"] as? String
            let sha256 = item["sha256"] as? String
            let backend = (item["backend"] as? String) ?? (id.hasPrefix("apple.mlx:") ? "mlx" : "coreai")

            return CoreAIRegisteredModel(id: id, path: path, sha256: sha256, backend: backend)
        }
    }

    static func model(id: String) -> CoreAIRegisteredModel? {
        registeredModels().first { $0.id == id }
    }

    /// Per-model availability for the daemon `availability()` report (TCK-0254 / FND-0236).
    ///
    /// Previously every registered model was hard-coded `available: false` with
    /// `inference_backend_unavailable`, so clients could never discover or route
    /// to a valid CoreAI/MLX registration. This probe mirrors the load-time
    /// gates (path allowlist, directory existence, attestation, CoreAI framework
    /// symbols for `apple.coreai:*`) without loading model weights.
    ///
    /// `supports` matches implemented behaviour:
    /// - `structuredOutput` only for `apple.mlx:*` (guided decoding); CoreAI
    ///   direct-path rejects `json_schema`.
    /// - `toolCalling` stays `true` (FND-0166 / TCK-0212): `sessions.create`
    ///   wires tools; direct-path respond/stream reject `tools` by name rather
    ///   than flipping this flag.
    /// - `image` only when `backend == "mlx-vlm"`.
    static func availabilityModels() -> [[String: Any]] {
        registeredModels().map { model in
            var entry: [String: Any] = [
                "id": model.id,
                "local": true,
                "supports": supports(for: model),
                "backend": model.backend
            ]

            let probe = availabilityProbe(for: model)
            entry["available"] = probe.available
            if let reason = probe.reason {
                entry["reason"] = reason
            }
            if let reasonCode = probe.reasonCode {
                entry["reasonCode"] = reasonCode
            }

            if let sha256 = model.sha256 {
                entry["sha256"] = sha256
            }

            return entry
        }
    }

    /// Capability flags that match what the daemon will actually serve for this
    /// registration (TCK-0254 / FND-0236). Kept as a pure function so unit tests
    /// can pin honesty without registering env state.
    static func supports(for model: CoreAIRegisteredModel) -> [String: Any] {
        let isMLX = model.id.hasPrefix("apple.mlx:")
        var supports: [String: Any] = [
            "text": true,
            "streaming": true,
            // MLX guided decoding (TCK-0110); CoreAI direct-path rejects json_schema.
            "structuredOutput": isMLX,
            // sessions.create wires tools; direct-path rejects by name (FND-0166).
            "toolCalling": true,
            "tokenCounting": false,
            "contextWindow": true
        ]
        if model.backend == "mlx-vlm" {
            supports["image"] = true
        } else {
            supports["image"] = false
        }
        return supports
    }

    /// Result of a non-loading availability probe for a single registration.
    static func availabilityProbe(for model: CoreAIRegisteredModel) -> (
        available: Bool,
        reason: String?,
        reasonCode: String?
    ) {
        guard isInferencePlatformSupported() else {
            return (false, "inferenceBackendUnavailable", "inference_backend_unavailable")
        }

        guard let path = model.path else {
            return (false, "missingRegistryPath", "missing_registry_path")
        }

        if let pathIssue = validateModelPath(path) {
            return (false, pathIssue.reason, pathIssue.reasonCode)
        }

        guard FileManager.default.fileExists(atPath: path) else {
            return (false, "modelDirectoryNotFound", "model_directory_not_found")
        }

        if verifyAttestation(model: model, directoryPath: path) != nil {
            return (false, "modelAttestationFailed", "model_attestation_failed")
        }

        // apple.coreai:* needs the weak-linked CoreAI.framework symbols at load.
        // MLX does not — path + allowlist is enough for discovery honesty.
        if model.id.hasPrefix("apple.coreai:"), !CoreAIRuntimeAvailability.isAvailable {
            return (false, "inferenceBackendUnavailable", "coreai_framework_unavailable")
        }

        return (true, nil, nil)
    }

    private static func isInferencePlatformSupported() -> Bool {
        if #available(macOS 27.0, iOS 27.0, *) {
            return true
        }
        return false
    }

    static func requestError(for modelId: String) -> JsonRpcError {
        guard let registered = model(id: modelId) else {
            return JsonRpcError.modelUnavailable(
                "Core AI model \"\(modelId)\" is not registered.",
                data: [
                    "code": "MODEL_NOT_FOUND",
                    "model": modelId,
                    "reasonCode": "model_not_found"
                ]
            )
        }

        // Prefer the same probe reasons availability() would surface so a
        // registered-but-unusable model does not claim a fictional "not
        // implemented yet" backend (TCK-0254 / FND-0236).
        let probe = availabilityProbe(for: registered)
        if !probe.available {
            let reasonCode = probe.reasonCode ?? "inference_backend_unavailable"
            // Path-shaped failures map to MODEL_NOT_FOUND (same family as loadSession);
            // attestation mismatch keeps MODEL_ATTESTATION_FAILED; framework/OS gaps
            // stay INFERENCE_BACKEND_UNAVAILABLE.
            let code: String
            switch reasonCode {
            case "model_not_found", "missing_registry_path", "model_directory_not_found":
                code = "MODEL_NOT_FOUND"
            case "model_attestation_failed":
                code = "MODEL_ATTESTATION_FAILED"
            default:
                code = "INFERENCE_BACKEND_UNAVAILABLE"
            }
            return JsonRpcError.modelUnavailable(
                "Core AI model \"\(modelId)\" is registered but not available (\(reasonCode)).",
                data: [
                    "code": code,
                    "model": modelId,
                    "reasonCode": reasonCode
                ]
            )
        }

        return JsonRpcError.modelUnavailable(
            "Core AI model \"\(modelId)\" is registered, but the inference backend is unavailable on this platform.",
            data: [
                "code": "INFERENCE_BACKEND_UNAVAILABLE",
                "model": modelId,
                "reasonCode": "inference_backend_unavailable"
            ]
        )
    }

    /// Attestation error for a model whose declared `sha256` did not match
    /// the on-disk model (FND-0212, TCK-0219). Fail-closed: callers must throw
    /// this instead of proceeding to load.
    static func attestationError(for modelId: String) -> JsonRpcError {
        JsonRpcError.modelUnavailable(
            "Core AI model \"\(modelId)\" failed sha256 attestation: the on-disk model no longer matches its declared digest.",
            data: [
                "code": "MODEL_ATTESTATION_FAILED",
                "model": modelId,
                "reasonCode": "model_attestation_failed"
            ]
        )
    }

    /// Verifies `model`'s declared `sha256` (if any) against a freshly
    /// computed manifest digest of `directoryPath`. Returns `nil` when there
    /// is nothing to verify (no `sha256` declared — attestation is opt-in and
    /// preserves prior behavior for models that don't declare one) or when
    /// the digest matches; returns the mismatch details otherwise so the
    /// caller can fail CLOSED (see `attestationError(for:)`).
    ///
    /// WHAT is digested (a deliberate, documented choice — FND-0212 flagged
    /// the prior code for echoing `sha256` without ever verifying it, so this
    /// must be honest about its own coverage too): model weights are
    /// directories, often many gigabytes across multiple shard files; hashing
    /// every byte on every load would make attestation cost scale with model
    /// size and could add seconds-to-minutes of latency to daemon startup or
    /// first load. Instead this hashes a compact STRUCTURAL manifest — the
    /// sorted list of "<relative-path>\0<byte-size>" for every regular file
    /// under the directory (recursively) — which costs O(file count), not
    /// O(bytes). This catches the common tamper (files added, removed, or
    /// resized — i.e. the model directory's contents were swapped for a
    /// different model), but it does NOT catch a same-size byte-for-byte
    /// content swap. That is an explicit boundary of this control, not an
    /// oversight: a full-content hash is available as a documented follow-up
    /// if the daemon later needs to defend against that stronger threat.
    static func verifyAttestation(model: CoreAIRegisteredModel, directoryPath: String) -> ModelAttestationMismatch? {
        guard let expected = model.sha256 else {
            return nil
        }

        let actual = manifestDigestHex(directoryPath: directoryPath)
        guard actual != expected else {
            return nil
        }

        return ModelAttestationMismatch(expected: expected, actual: actual)
    }

    /// SHA-256 hex digest of the structural manifest described above. Never
    /// throws: an unreadable directory (permission error, a race with a
    /// concurrent delete, etc.) digests to a fixed sentinel line instead of
    /// crashing or silently skipping verification — the sentinel will simply
    /// never match a real declared `sha256`, so unreadability fails CLOSED by
    /// construction rather than needing special-case handling at call sites.
    private static func manifestDigestHex(directoryPath: String) -> String {
        let manifest = manifestLines(directoryPath: directoryPath).sorted().joined(separator: "\n")
        let digest = SHA256.hash(data: Data(manifest.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func manifestLines(directoryPath: String) -> [String] {
        let root = URL(fileURLWithPath: directoryPath)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            return ["<missing-path>"]
        }

        guard isDirectory.boolValue else {
            // Single-file registry path (e.g. a standalone bundle file that
            // resolves to one file rather than a directory): manifest of the
            // one entry.
            let attributes = try? FileManager.default.attributesOfItem(atPath: root.path)
            let size = (attributes?[.size] as? Int) ?? -1
            return ["\(root.lastPathComponent)\0\(size)"]
        }

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ["<unreadable-directory>"]
        }

        var lines: [String] = []
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else {
                continue
            }
            let relativePath = fileURL.path.hasPrefix(root.path)
                ? String(fileURL.path.dropFirst(root.path.count))
                : fileURL.path
            lines.append("\(relativePath)\0\(values.fileSize ?? -1)")
        }
        return lines
    }

    private static func isSafeModelId(_ modelId: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-")
        return !modelId.isEmpty
            && modelId.unicodeScalars.allSatisfy { allowed.contains($0) }
            && !modelId.contains("..")
            && !modelId.contains("//")
    }

    /// Internal so inference backends (e.g. `MLXInferenceBackend.runGeneration`) can enforce the
    /// same root allowlist + traversal/symlink check that `availabilityModels()` reports — closing
    /// the gap where the direct-path could load a model from outside the allowlist (ADR-0006 §7).
    static func validateModelPath(_ rawPath: String) -> (reason: String, reasonCode: String)? {
        guard rawPath.hasPrefix("/") else {
            return ("modelPathMustBeAbsolute", "model_not_found")
        }

        if rawPath.contains("\0") || rawPath.split(separator: "/").contains("..") {
            return ("unsafeModelPath", "model_not_found")
        }

        let roots = allowedModelRoots()
        guard !roots.isEmpty else {
            return ("modelRootAllowlistMissing", "model_not_found")
        }

        let canonicalPath = canonicalizedPath(rawPath)
        let allowed = roots.contains { root in
            canonicalPath == root || canonicalPath.hasPrefix(root + "/")
        }

        return allowed ? nil : ("modelPathOutsideAllowlist", "model_not_found")
    }

    private static func allowedModelRoots() -> [String] {
        guard let raw = ProcessInfo.processInfo.environment[modelRootsEnvironmentKey] else {
            return []
        }

        return raw
            .split(separator: ":")
            .map(String.init)
            .filter { $0.hasPrefix("/") && !$0.contains("\0") }
            .map(canonicalizedPath)
    }

    /// Fully resolves the path, including multi-hop symlink chains, before the allowlist prefix
    /// comparison (TCK-0119 / FND-0072). `destinationOfSymbolicLink(atPath:)` only peels the
    /// immediate target of a SINGLE symlink and — for a relative target — resolves it against the
    /// process's current working directory rather than the symlink's own directory, so it is not
    /// equivalent to `realpath(3)`. `resolvingSymlinksInPath()` resolves the entire chain (backed by
    /// `realpath(3)` when the path exists on disk), matching what the OS actually opens at inference
    /// time and closing the gap where a two-hop chain inside an allowed root could land outside it.
    private static func canonicalizedPath(_ rawPath: String) -> String {
        URL(fileURLWithPath: rawPath).resolvingSymlinksInPath().path
    }
}
