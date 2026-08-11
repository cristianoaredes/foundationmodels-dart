import Foundation

/// Shared cumulative-snapshot → incremental-delta helpers (TCK-0257 / FND-0239).
///
/// Apple `LanguageModelSession.streamResponse` yields **cumulative** snapshots. Diffing via
/// Character-view `hasPrefix` + `dropFirst(previous.count)` re-walks the whole prefix on every
/// snapshot (`String.count`, `hasPrefix`, and `dropFirst` are each O(n) over grapheme clusters).
/// UTF-8 keeps `count` O(1) on native strings and a single byte walk for the prefix check;
/// suffix materialization is O(|delta|).
///
/// Structured streams similarly re-parsed + double-serialized every tick; the trackers below
/// keep a raw/canonical cursor so unchanged snapshots skip that work.
enum StreamingDelta {
    // MARK: - Text (cumulative snapshot → delta)

    /// Incremental text delta for the common monotonic-snapshot case.
    /// Non-prefix `next` returns `next` in full (same contract as the historical private
    /// `textDelta` helper — callers without a replace flag treat it as a full snapshot).
    static func textDelta(previous: String, next: String) -> String {
        computeSnapshotDelta(previous: previous, next: next).delta
    }

    /// Computes the next streaming chunk from a pair of cumulative snapshots
    /// (TCK-0121 / FND-0074, TCK-0257 / FND-0239).
    ///
    /// - Prefix (common): incremental suffix, `isSnapshotReplace = false`.
    /// - Non-prefix (rare self-correction): full `next`, `isSnapshotReplace = true`.
    ///   Callers MUST replace their accumulated buffer with `delta` when the flag is true.
    static func computeSnapshotDelta(
        previous: String,
        next: String
    ) -> (delta: String, isSnapshotReplace: Bool) {
        if previous.isEmpty {
            return (next, false)
        }

        let prevUTF8 = previous.utf8
        let nextUTF8 = next.utf8
        // `String.UTF8View.count` is O(1) for native Swift strings (stored UTF-8 length).
        let prevCount = prevUTF8.count
        guard nextUTF8.count >= prevCount, nextUTF8.starts(with: prevUTF8) else {
            return (next, true)
        }
        if nextUTF8.count == prevCount {
            return ("", false)
        }
        // `dropFirst` on UTF8View is O(1) index math; decoding copies only the suffix.
        let suffix = nextUTF8.dropFirst(prevCount)
        return (String(decoding: suffix, as: UTF8.self), false)
    }

    // MARK: - Structured completeness gate (MLX partial text)

    /// Cheap pre-check before `JSONSerialization` on partial guided-decoding text.
    /// Rejects obvious incompletes (`{"a":` …) so the hot path skips parse attempts
    /// until the buffer at least opens and closes with matching container delimiters.
    static func mightBeCompleteJSON(_ text: String) -> Bool {
        let utf8 = text.utf8
        guard !utf8.isEmpty else { return false }

        // Trim ASCII whitespace without allocating a new String.
        var start = utf8.startIndex
        var end = utf8.endIndex
        while start < end, isASCIIWhitespace(utf8[start]) {
            utf8.formIndex(after: &start)
        }
        guard start < end else { return false }
        utf8.formIndex(before: &end)
        while end > start, isASCIIWhitespace(utf8[end]) {
            utf8.formIndex(before: &end)
        }
        // `end` now points at the last non-whitespace byte.
        let first = utf8[start]
        let last = utf8[end]
        switch first {
        case UInt8(ascii: "{"):
            return last == UInt8(ascii: "}")
        case UInt8(ascii: "["):
            return last == UInt8(ascii: "]")
        case UInt8(ascii: "\""):
            // At least `""`.
            return start < end && last == UInt8(ascii: "\"")
        default:
            // number / true / false / null — let the parser decide.
            return true
        }
    }

    private static func isASCIIWhitespace(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ")
            || byte == UInt8(ascii: "\t")
            || byte == UInt8(ascii: "\n")
            || byte == UInt8(ascii: "\r")
    }

    // MARK: - Structured emit trackers

    /// Apple guided-generation path: dedupe by raw JSON string identity so identical
    /// cumulative snapshots skip parse + equality serialize entirely.
    struct RawJSONEmitTracker {
        private(set) var previousRaw: String?
        private(set) var lastObject: Any?

        /// - Returns: object to emit, or `nil` when the raw snapshot is empty/unchanged/unparseable.
        mutating func consider(
            rawJSON: String,
            parse: (String) throws -> Any?
        ) rethrows -> Any? {
            guard !rawJSON.isEmpty else { return nil }
            if rawJSON == previousRaw {
                return nil
            }
            guard let object = try parse(rawJSON) else {
                return nil
            }
            previousRaw = rawJSON
            lastObject = object
            return object
        }
    }

    /// MLX guided-decoding path: accumulate token text; only parse when the buffer
    /// might be complete JSON; compare a single canonical serialization against the
    /// previous one (half the work of serializing both sides every tick).
    struct AccumulatedJSONEmitTracker {
        private(set) var previousCanonical: Data?
        private(set) var lastObject: Any?

        /// - Returns: object to emit, or `nil` when incomplete/unchanged/unparseable.
        mutating func consider(
            accumulatedText: String,
            parse: (String) throws -> Any?
        ) rethrows -> Any? {
            guard mightBeCompleteJSON(accumulatedText) else {
                return nil
            }
            guard let object = try parse(accumulatedText) else {
                return nil
            }
            if let canonical = canonicalJSONData(object) {
                if canonical == previousCanonical {
                    return nil
                }
                previousCanonical = canonical
                lastObject = object
                return object
            }
            // Non-container / non-JSONSerialization values: fall back to always-emit once parsed.
            lastObject = object
            return object
        }

        /// Force a final consider of fully-formed text (skips the completeness gate — the
        /// terminal `result.text` is expected to be complete; still dedupes via canonical Data).
        mutating func considerFinal(
            text: String,
            parse: (String) throws -> Any
        ) throws -> Any? {
            let object = try parse(text)
            if let canonical = canonicalJSONData(object) {
                if canonical == previousCanonical {
                    return nil
                }
                previousCanonical = canonical
                lastObject = object
                return object
            }
            lastObject = object
            return object
        }
    }

    /// Stable canonical form for equality — single serialize, compared as `Data`.
    static func canonicalJSONData(_ value: Any) -> Data? {
        guard JSONSerialization.isValidJSONObject(value) else {
            return nil
        }
        return try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }
}
