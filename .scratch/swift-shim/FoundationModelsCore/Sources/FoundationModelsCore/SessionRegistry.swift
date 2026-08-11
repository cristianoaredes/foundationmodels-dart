import Foundation

/// Thread-safe registry for `FoundationModelsCore`'s in-flight session state, keyed by
/// session id (TCK-0129).
///
/// `FoundationModelsCore` is shared as a single instance across every daemon connection
/// (`JsonRpcHandler.runtime`, constructed once in `main.swift`). The dictionary that used to
/// back `sessions` (a plain `public var sessions: [String: Any]`) had no synchronization at
/// all: concurrent mutation of a Swift `Dictionary` from multiple threads — even on different
/// keys — is undefined behavior, not just a logic race; it can crash or corrupt the table.
/// This type closes that gap with the same `NSLock`-guarded pattern already used by
/// `GenerationTaskRegistry` (`swift/Sources/FoundationModelsDaemon/GenerationTaskRegistry.swift`)
/// — that type lives in a different Swift package/module (`FoundationModelsDaemon`), so it
/// can't be imported/reused here; the same pattern is reimplemented locally instead.
///
/// Values are stored as `Any` rather than a concrete `LanguageModelSession` so this file (and
/// the `FoundationModelsCore` property that owns an instance of it) stays framework-agnostic
/// and compiles even where `FoundationModels` isn't importable — the same reason `sessions`
/// was originally declared `[String: Any]`. Callers downcast at the point of use, same as
/// before this ticket.
///
/// Note on scope: locking each individual `get`/`set`/`remove` call prevents the dictionary
/// itself from being corrupted by concurrent mutation on distinct OR overlapping keys — the
/// property this ticket targets ("two concurrent connections creating/using distinct sessions
/// must not corrupt the dictionary"). It does NOT make higher-level, multi-step sequences
/// atomic — e.g. `FoundationModelsCore.sessionFor` does a `get` and, only on a miss, later a
/// `set`; two connections racing on the same brand-new `sessionId` can both miss and both
/// build a session, with the second `set` winning. That is a benign duplicate-construction
/// race (wasted work, not memory corruption) and is unchanged by this ticket, which scopes to
/// accessor thread-safety, matching `GenerationTaskRegistry`'s own granularity (it doesn't
/// offer a compound "register-if-absent" either).
///
/// TCK-0230 / FND-0174: each entry tracks `lastUsedAt`. Access paths (`get`/`set`/`count`/
/// `oldestAgeSeconds`) reap idle entries by TTL and, when a max entry count is configured,
/// evict the least-recently-used overflow. No background timer — reap-on-access only.
final class SessionRegistry: @unchecked Sendable {
    /// Default cap for the live native-session table (DES-0080 / FND-0174).
    static let defaultMaxEntries = 256
    /// Default idle TTL: 30 minutes (DES-0080 / FND-0174).
    static let defaultTTL: TimeInterval = 30 * 60

    private struct Entry {
        var value: Any
        var lastUsedAt: Date
    }

    private let lock = NSLock()
    private var storage: [String: Entry] = [:]
    private let maxEntries: Int?
    private let ttl: TimeInterval?
    private let clock: () -> Date

    /// - Parameters:
    ///   - maxEntries: When non-nil, `set` evicts LRU entries once the table exceeds this
    ///     size. Pass `nil` to disable the cap (used for lightweight side-tables).
    ///   - ttl: Idle lifetime. Pass `nil` to disable TTL reaping.
    ///   - clock: Injectable clock for deterministic TTL tests.
    init(
        maxEntries: Int? = SessionRegistry.defaultMaxEntries,
        ttl: TimeInterval? = SessionRegistry.defaultTTL,
        clock: @escaping () -> Date = Date.init
    ) {
        self.maxEntries = maxEntries
        self.ttl = ttl
        self.clock = clock
    }

    /// Returns the stored value for `id`, or `nil` if absent / reaped. Touches `lastUsedAt`.
    func get(_ id: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        let now = clock()
        reapLocked(now: now)
        guard var entry = storage[id] else { return nil }
        entry.lastUsedAt = now
        storage[id] = entry
        return entry.value
    }

    /// Stores `value` for `id`, replacing any existing entry. Touches `lastUsedAt`, reaps
    /// expired entries, then evicts LRU overflow when over cap.
    func set(_ id: String, _ value: Any) {
        lock.lock()
        defer { lock.unlock() }
        let now = clock()
        reapLocked(now: now)
        storage[id] = Entry(value: value, lastUsedAt: now)
        evictOverflowLocked()
    }

    /// Removes the entry for `id`. Returns `true` when an entry was present (and removed),
    /// `false` when there was nothing to remove — mirrors what
    /// `sessions.removeValue(forKey:) != nil` used to express inline at the one call site
    /// (`FoundationModelsCore.disposeSession`).
    @discardableResult
    func remove(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage.removeValue(forKey: id) != nil
    }

    /// Current number of entries after reap-on-access. Exposed for tests and `health()`.
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        reapLocked(now: clock())
        return storage.count
    }

    /// Age in seconds of the least-recently-used entry after reap, or `nil` when empty.
    var oldestAgeSeconds: Double? {
        lock.lock()
        defer { lock.unlock() }
        let now = clock()
        reapLocked(now: now)
        guard let oldest = storage.values.map(\.lastUsedAt).min() else { return nil }
        return now.timeIntervalSince(oldest)
    }

    private func reapLocked(now: Date) {
        guard let ttl else { return }
        let cutoff = now.addingTimeInterval(-ttl)
        storage = storage.filter { _, entry in entry.lastUsedAt >= cutoff }
    }

    private func evictOverflowLocked() {
        guard let maxEntries, storage.count > maxEntries else { return }
        let overflow = storage.count - maxEntries
        let victims = storage
            .sorted { $0.value.lastUsedAt < $1.value.lastUsedAt }
            .prefix(overflow)
        for (id, _) in victims {
            storage.removeValue(forKey: id)
        }
    }
}
