import Foundation

/// Process-wide LRU cache for heavy MLX / CoreAI model handles (TCK-0258 / FND-0240 / DES-0098).
///
/// Before this type, every `apple.mlx:*` / `apple.coreai:*` request reloaded weights from disk
/// (`LLMModelFactory.loadContainer`, `CoreAILanguageModel(resourcesAt:)`) and `sessions.prewarm`
/// was a documented no-op. This cache:
///
/// 1. Keys handles by `(kind, modelId, standardized registryPath)` so text/VLM/CoreAI never collide.
/// 2. Coalesces concurrent first-loads for the same key into a single `loader` invocation.
/// 3. Evicts least-recently-used entries once `maxEntries` is exceeded (default **2** — models are
///    multi-GB; keep the working set small).
/// 4. Exposes hit/miss/load counters for unit tests (not exported on the JSON-RPC surface yet).
///
/// Thread-safety: this is an `actor`. Callers `await` every access. Values must be `Sendable`
/// (MLX `ModelContainer` already is; CoreAI wraps its model in `CoreAIModelHandle`).
public actor ModelHandleCache {
    /// Shared daemon-wide instance used by production backends.
    public static let shared = ModelHandleCache()

    /// Default cap: two resident model handles. Override in tests or specialized hosts.
    public static let defaultMaxEntries = 2

    /// Discriminator so a text LLM, a VLM, and a CoreAI `.aimodel` at the same path stay distinct.
    public enum Kind: String, Sendable, Hashable {
        case mlxLLM
        case mlxVLM
        case coreAI
    }

    /// Cache key. `registryPath` is standardized (`URL.standardizedFileURL.path`) so
    /// `/foo/../bar` and `/bar` hit the same entry.
    public struct Key: Hashable, Sendable {
        public let kind: Kind
        public let modelId: String
        public let registryPath: String

        public init(kind: Kind, modelId: String, registryPath: String) {
            self.kind = kind
            self.modelId = modelId
            self.registryPath = URL(fileURLWithPath: registryPath).standardizedFileURL.path
        }
    }

    private struct Entry {
        var handle: any Sendable
        var lastUsedAt: ContinuousClock.Instant
    }

    private var storage: [Key: Entry] = [:]
    private var inflight: [Key: Task<any Sendable, Error>] = [:]
    private let maxEntries: Int
    private let clock: @Sendable () -> ContinuousClock.Instant

    /// Number of times `getOrLoad` returned a resident handle without calling `loader`.
    public private(set) var hits: Int = 0
    /// Number of times `getOrLoad` had to start (or join) a load.
    public private(set) var misses: Int = 0
    /// Number of times `loader` actually ran to completion successfully.
    public private(set) var loads: Int = 0

    /// - Parameters:
    ///   - maxEntries: LRU cap. Must be ≥ 1.
    ///   - clock: Injectable clock for deterministic LRU tests.
    public init(
        maxEntries: Int = ModelHandleCache.defaultMaxEntries,
        clock: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }
    ) {
        precondition(maxEntries >= 1, "ModelHandleCache.maxEntries must be ≥ 1")
        self.maxEntries = maxEntries
        self.clock = clock
    }

    /// Current number of resident handles.
    public var count: Int { storage.count }

    /// Drops every resident handle and cancels in-flight loads. Test isolation only.
    public func removeAll() {
        for (_, task) in inflight {
            task.cancel()
        }
        inflight.removeAll()
        storage.removeAll()
        hits = 0
        misses = 0
        loads = 0
    }

    /// Returns the resident handle for `key` without loading, or `nil` on a miss.
    /// Touches LRU order on hit. Used by tests to assert prewarm populated the cache.
    public func peek<T: Sendable>(_ key: Key, as type: T.Type = T.self) -> T? {
        guard var entry = storage[key] else { return nil }
        entry.lastUsedAt = clock()
        storage[key] = entry
        return entry.handle as? T
    }

    /// Returns a cached handle or loads one via `loader`, coalescing concurrent first-loads.
    ///
    /// - On hit: increments `hits`, touches LRU, returns the stored handle.
    /// - On miss with in-flight load: joins that task (no second `loader` call).
    /// - On cold miss: runs `loader` once, stores the result, evicts LRU overflow, increments
    ///   `loads` on success. A failing `loader` is not stored and is rethrown to every waiter.
    public func getOrLoad<T: Sendable>(
        key: Key,
        as type: T.Type = T.self,
        loader: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        if var entry = storage[key] {
            hits += 1
            entry.lastUsedAt = clock()
            storage[key] = entry
            guard let typed = entry.handle as? T else {
                // Kind/type mismatch on an existing key — treat as miss and reload.
                storage.removeValue(forKey: key)
                return try await loadAndStore(key: key, loader: loader)
            }
            return typed
        }

        misses += 1

        if let existing = inflight[key] {
            let value = try await existing.value
            guard let typed = value as? T else {
                throw ModelHandleCacheError.typeMismatch(key: key, expected: String(describing: T.self))
            }
            return typed
        }

        return try await loadAndStore(key: key, loader: loader)
    }

    private func loadAndStore<T: Sendable>(
        key: Key,
        loader: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        let task = Task<any Sendable, Error> {
            try await loader()
        }
        inflight[key] = task
        defer { inflight[key] = nil }

        do {
            let value = try await task.value
            guard let typed = value as? T else {
                throw ModelHandleCacheError.typeMismatch(key: key, expected: String(describing: T.self))
            }
            storage[key] = Entry(handle: typed, lastUsedAt: clock())
            loads += 1
            evictOverflow()
            return typed
        } catch {
            // Do not cache failures — next caller retries.
            throw error
        }
    }

    private func evictOverflow() {
        guard storage.count > maxEntries else { return }
        let overflow = storage.count - maxEntries
        let victims = storage
            .sorted { $0.value.lastUsedAt < $1.value.lastUsedAt }
            .prefix(overflow)
        for (key, _) in victims {
            storage.removeValue(forKey: key)
        }
    }
}

/// Typed errors from `ModelHandleCache` (internal / test-facing; backends map their own errors).
public enum ModelHandleCacheError: Error, CustomStringConvertible, Sendable {
    case typeMismatch(key: ModelHandleCache.Key, expected: String)

    public var description: String {
        switch self {
        case .typeMismatch(let key, let expected):
            return "ModelHandleCache type mismatch for \(key.kind.rawValue)/\(key.modelId): expected \(expected)"
        }
    }
}
