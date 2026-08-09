# Upstream ios-bridge extensions — executable specification (U1–U9)

| | |
|---|---|
| **Status** | Proposed |
| **Audience** | Implementers working in the `foundationmodels-js` monorepo (macOS-only toolchain) |
| **Target files** | `swift/ios-bridge/Sources/FoundationModelsIOSBridge/*.swift` (surface only); logic lives in `swift/FoundationModelsCore` |
| **Consumer** | Flutter plugin `foundationmodels_apple` (`FoundationModelsPlugin.swift`), which already compiles against the *target* API defined here |
| **Normative references (in this repo)** | `docs/protocol.md` (daemon wire protocol v2), `swift/ios-bridge/Sources/FoundationModelsIOSBridge/Bridge.swift` (current surface), `swift/FoundationModelsCore/**` (existing logic) |

This document is self-contained: all daemon semantics that the ios-bridge must
mirror are restated inline. Reading `docs/protocol.md` is still recommended for
byte-level fixtures, but no external conversation or ADR is required.

---

## 0. Shared contract (applies to every ticket)

### 0.1 Current bridge surface

`FoundationModelsBridge` is an `@objc` singleton (`FoundationModelsBridge.shared`)
exposing:

```swift
func health() -> [String: Any]
func availability() -> [String: Any]
func capabilities() -> [String: Any]
func createSession(config: [String: Any]) -> [String: Any]
func disposeSession(sessionId: String) -> [String: Any]
func respond(input: [String: Any], config: [String: Any]) async throws -> [String: Any]
func respond(params: [String: Any]) async throws -> [String: Any]
func respondObjC(input: [String: Any], config: [String: Any],
                 completion: @escaping ([String: Any]?, Error?) -> Void)
```

All methods exchange `[String: Any]` dictionaries in the **daemon-shaped params**
format — the exact same key layout the daemon's `JsonRpcHandler` accepts on the
socket. The extensions below keep that invariant: params and results are
byte-compatible with the daemon's v2 protocol wherever the daemon has an
equivalent method.

### 0.2 Architectural principle (non-negotiable)

The ios-bridge is a *thin in-process surface*. Each new method MUST call the same
`FoundationModelsCore` entry points that the daemon's `JsonRpcHandler` calls for
the equivalent JSON-RPC method. No model logic (schema conversion, transcript
handling, token counting, vision, cancellation policy) may be reimplemented or
forked inside the bridge. If a behavior differs between daemon and bridge, that
is a bug in the bridge.

### 0.3 Error contract (NSError bridging)

The Flutter plugin unwraps thrown errors as `NSError` and reads:

- `userInfo["jsonRpcCode"]` — `Int`, the JSON-RPC numeric code (e.g. `-32602`,
  `-32603`, `-32001`).
- `userInfo["data"]` — `[String: Any]`, the daemon's `error.data` dictionary,
  which MUST contain the stable machine-readable `"code"` string (e.g.
  `CONTEXT_OVERFLOW`) plus any structured fields the daemon attaches
  (`keyword`/`path`, `toolName`/`callbackCode`, `contextSize`/`tokenCount`,
  `resetDate`, `pccFailureKind`/`retryable`, ...).
- `localizedDescription` — the human message.

Therefore every `throws` method added here MUST throw an error that bridges to
`NSError` with exactly those `userInfo` keys populated. The core's
`NativeErrorContract` already produces this shape for the daemon; reuse it.
Anything that escapes without `data.code` degrades to `UNKNOWN_MODEL_ERROR` on
the consumer side — acceptable only for truly unexpected traps, never for known
failure modes. Stream-terminal failures follow the same payload shape inside an
`error` event (see 0.4).

### 0.4 Stream event vocabulary (protocol v2)

Streamed generations emit ordered event dictionaries. Every event carries
`"type"` plus `"requestId"`; `"sessionId"` and `"traceId"` are included whenever
available. Types:

`run_started` · `message_start` · `text_delta` · `structured_delta` ·
`tool_call_start` · `tool_call_delta` · `tool_call_result` · `message_end` ·
`done` · `error`

Additional type used by duplex tool calling (U7): `tool_call_request`.

Ordering guarantees (mirroring the daemon):

1. `run_started` is always first; `message_start` precedes any content delta.
2. A stream ends with **exactly one** terminal event: `done` (success) or
   `error` (any failure, including cancellation). No events after a terminal
   event.
3. `structured_delta` streams carry guided-generation partial JSON; the final
   validated object is reflected in `message_end` / the unary-style result
   inside `done`, exactly as the daemon shapes it.

### 0.5 Stable error codes relevant to these tickets

`error.data.code` values referenced below (full table in `docs/protocol.md`):

- Transport/params: `INVALID_REQUEST`, `METHOD_NOT_FOUND`, `INVALID_PARAMS`,
  `UNKNOWN_MODEL_ERROR`.
- Model/session: `APPLE_MODEL_UNAVAILABLE` (+`reasonCode`),
  `CONTEXT_OVERFLOW` (+`contextSize`/`tokenCount` on SDK 27),
  `GUARDRAIL_VIOLATION`, `MODEL_REFUSAL`, `RATE_LIMITED` (+`resetDate`),
  `MODEL_TIMEOUT`, `SESSION_BUSY`, `TRANSCRIPT_MUTATION_WHILE_RESPONDING`,
  `GENERATION_CANCELLED`, `STRUCTURED_OUTPUT_VALIDATION_FAILED`.
- Schema/options: `UNSUPPORTED_SCHEMA_TYPE` (+`keyword`/`path`),
  `UNSUPPORTED_OPTION`, `UNSUPPORTED_OPERATION`,
  `UNSUPPORTED_TRANSCRIPT_CONTENT`, `UNSUPPORTED_GENERATION_GUIDE`,
  `UNSUPPORTED_LANGUAGE_OR_LOCALE`.
- Tools: `TOOL_CALLBACKS_REQUIRE_STREAMING`, `TOOL_EXECUTION_FAILED`
  (+`toolName`/`callbackCode`), `SYSTEM_TOOL_UNAVAILABLE`.
- Multimodal/vision/feedback: `MULTIMODAL_INPUT_UNAVAILABLE`,
  `VISION_OCR_UNAVAILABLE`, `VISION_BARCODE_UNAVAILABLE`,
  `FEEDBACK_ATTACHMENT_UNAVAILABLE`.
- PCC (U9): `PCC_UNAVAILABLE`, `PCC_QUOTA_EXHAUSTED` (+`pccFailureKind`,
  `retryable`).

### 0.6 Swift 6 concurrency baseline

- All new `async` methods are `nonisolated` on the bridge singleton (matching
  the existing `respond(params:)`), safe to call from any executor.
- Event/result payloads are `[String: Any]` containing only value types
  (String, numbers, Bool, nested arrays/dicts). Where strict concurrency
  complains about `[String: Any]` crossing isolation boundaries, follow the
  pattern already used in the bridge (`nonisolated(unsafe)` / `@unchecked
  Sendable` wrappers) rather than weakening call-site semantics.
- Callback closures that cross tasks are `@Sendable`.

---

## U1 — `respondStream(params:onEvent:)` — in-process streaming

**Goal.** Expose the core's streaming generation (`StreamingDelta.swift`, the
same engine behind the daemon's `sessions.stream` handler) as an in-process
async API with a per-event callback, emitting protocol-v2 events.

### Proposed Swift API

```swift
extension FoundationModelsBridge {
    /// Streams a generation, emitting daemon-v2-shaped event dictionaries.
    ///
    /// - Parameter params: daemon-shaped `foundationmodels.sessions.stream`
    ///   params (`sessionId?`, `model?`, `input`, `instructions?`, `options?`,
    ///   guided-generation keys, `tools?`, `generationId?`, `requestId?`, ...).
    /// - Parameter onEvent: invoked serially, in emission order, once per
    ///   event; never concurrently. Called on an unspecified background
    ///   executor — consumers must hop threads themselves if needed.
    /// - Throws: only for pre-stream failures (invalid params, unknown
    ///   session, unsupported schema/options, callback tools on a non-stream
    ///   path, etc.). See Semantics for the terminal-failure rule.
    public func respondStream(
        params: [String: Any],
        onEvent: @escaping @Sendable ([String: Any]) -> Void
    ) async throws
}
```

Plugin callsite (already written, `FoundationModelsPlugin.startStreaming`):
`try await FoundationModelsBridge.shared.respondStream(params: params) { event in ... }`.
The plugin enriches each event with `requestId` when absent; the bridge SHOULD
set `requestId` itself (to `params["generationId"] ?? params["requestId"] ??`
a generated `gen_*` id) so other hosts need no enrichment.

### Semantics

- **Correlation id.** The generation's `requestId` equals
  `params.generationId ?? params.requestId ?? <generated>`. The same value is
  used by U6 (`cancelGeneration`). It must be echoed in every event.
- **Lifecycle.** Before any event is emitted, validate params exactly as the
  daemon's `sessions.stream` handler does: unknown `sessionId` → throw the
  same error the daemon produces for an unknown session (same `data.code` —
  do not invent a bridge-specific one); unsupported schema keyword →
  `UNSUPPORTED_SCHEMA_TYPE` with `keyword`/`path`; callback tools present →
  allowed here (stream-only), see U7; MLX/CoreAI model with
  tools/contextOptions → `UNSUPPORTED_OPTION` (U8).
- **Terminal rule.** Once the first event has been emitted, `respondStream`
  MUST NOT throw: any subsequent failure (guardrail, overflow mid-generation,
  cancellation, transport-equivalent internal error) is delivered as a
  terminal `error` event with the daemon-shaped payload, and the function
  returns normally. Rationale: the consumer's catch path also emits an `error`
  event; throwing after events would double-terminate the stream.
- **Event sequence.** `run_started` → `message_start` → content deltas
  (`text_delta` or `structured_delta`; `tool_call_*` when U7 tools are
  involved) → `message_end` → `done`, with exactly one terminal event per
  0.4. `sessionId`/`traceId` attached when available.
- **Empty stream.** If the model produces zero content deltas, the stream
  still emits `run_started`, `message_start`, `message_end`, `done` (with the
  empty result in `done`, mirroring the daemon). Never emit `done` without the
  preceding lifecycle events.
- **Backpressure.** `onEvent` is called serially from the streaming task; a
  slow callback slows the stream. Document that callbacks must be
  non-blocking (the Flutter plugin only enqueues onto a serial dispatch
  queue).
- **Cancellation.** `cancelGeneration(generationId:)` (U6) cancels the
  underlying streaming `Task`; the stream terminates with
  `error`/`GENERATION_CANCELLED`, even if cancellation lands before the first
  delta (cancel-before-first-delta: no content events, terminal error only).
- **Instructions precedence.** On an existing session, `instructions` in
  params are ignored (first-request-wins), identical to the daemon.

### Error mapping

| Condition | Surface | `data.code` |
|---|---|---|
| Malformed params (missing `input`, bad types) | throw (pre-stream) | `INVALID_PARAMS` |
| Unknown `sessionId` | throw (pre-stream) | daemon's session-not-found code (parity, do not invent) |
| Unsupported schema keyword | throw | `UNSUPPORTED_SCHEMA_TYPE` (+`keyword`, `path`) |
| MLX/CoreAI + tools/contextOptions | throw | `UNSUPPORTED_OPTION` |
| Model unavailable | throw | `APPLE_MODEL_UNAVAILABLE` (+`reasonCode`) |
| Context overflow (upfront) | throw or terminal `error` event — match daemon timing | `CONTEXT_OVERFLOW` (+`contextSize`, `tokenCount` on SDK 27) |
| Guardrail / refusal mid-stream | terminal `error` event | `GUARDRAIL_VIOLATION` / `MODEL_REFUSAL` |
| Rate limit / timeout | terminal `error` event | `RATE_LIMITED` (+`resetDate`) / `MODEL_TIMEOUT` |
| Concurrent generation on same session | throw | `SESSION_BUSY` |
| Cancellation (explicit U6 or implicit abandon) | terminal `error` event | `GENERATION_CANCELLED` |
| Structured output failed validation | terminal `error` event | `STRUCTURED_OUTPUT_VALIDATION_FAILED` (never includes `rawContent`) |

### Implementation notes

- Reuse `FoundationModelsCore/StreamingDelta.swift` and the daemon's
  `sessions.stream` handler flow (`JsonRpcHandler`) as the blueprint — ideally
  factor the shared event-assembly into a core helper both call.
- Maintain a `generationId → Task` registry (shared with U6) protected by a
  lock or actor; insert before the first event, remove on terminal event.
- Swift 6: the `onEvent` closure is `@Sendable`; event dicts contain value
  types only. If the existing bridge pattern uses `nonisolated(unsafe)` for
  the singleton state, follow it.
- Byte-parity: event dictionaries must be key-for-key identical to the
  daemon's v2 events for the same generation (fixture-compare against
  recorded daemon traffic).

### Tests

`swift test` (mirror the daemon handler tests):

1. Text stream: events in order `run_started → message_start → text_delta+ →
   message_end → done`; concatenated deltas equal the unary `respond` output
   for the same prompt.
2. Guided stream: `structured_delta+ → message_end → done`; final object
   validates against the schema.
3. Empty output: lifecycle events present, zero deltas, `done` terminal.
4. Unknown session: throws, zero events.
5. Unsupported schema keyword: throws `UNSUPPORTED_SCHEMA_TYPE` with
   `keyword`/`path`.
6. Terminal rule: force a mid-stream failure → exactly one `error` event, no
   throw, no `done`.
7. Event parity: golden fixtures from the daemon's recorded v2 streams diff
   clean (excluding volatile ids/timestamps).

On-device smoke equivalent: `scripts/smoke/streaming.mjs` (deltas arrive
incrementally, not one batch).

### Acceptance criteria

- [ ] Signature above exists on `FoundationModelsBridge` and compiles under Swift 6 strict concurrency.
- [ ] All 10 v2 event types reachable; ordering and single-terminal-event invariants hold.
- [ ] Pre-stream failures throw typed errors (0.3); post-first-event failures are terminal `error` events only.
- [ ] Events byte-parity-checked against daemon fixtures.
- [ ] Streaming smoke passes on device.

---

## U2 — `countTokens(params:)` — native token counting

**Goal.** Expose `SystemLanguageModel.tokenCount(for:)` in-process with the
same params/result shape as the daemon's `foundationmodels.context.countTokens`.

### Proposed Swift API

```swift
extension FoundationModelsBridge {
    /// Counts tokens for the given input without generating.
    /// `params` mirrors the daemon's `context.countTokens` params
    /// (`input` or `sessionId`-based transcript counting, per protocol).
    public func countTokens(params: [String: Any]) async throws -> [String: Any]
}
```

Plugin callsite: `result(try await bridge.countTokens(params: params))` — exact match.

### Semantics

- Result dictionary is byte-identical to the daemon's `context.countTokens`
  result (token count plus the `estimated` flag and any breakdown fields the
  daemon emits).
- `estimated: false` only when the count is natively measured (SDK 27
  `tokenCount(for:)`); estimation paths must keep `estimated: true`.
- Accepts the same input shapes as generation params (text and multimodal
  content parts); multimodal parts that cannot be tokenized fail as below.
- Does not create or mutate sessions.

### Error mapping

| Condition | `data.code` |
|---|---|
| Missing/invalid input | `INVALID_PARAMS` |
| Model unavailable | `APPLE_MODEL_UNAVAILABLE` (+`reasonCode`) |
| Untokenizable multimodal part | `MULTIMODAL_INPUT_UNAVAILABLE` |

### Implementation notes

- Call the identical core path used by the daemon's `context.countTokens`
  handler; zero new logic in the bridge.
- Async because the underlying API is async; keep `nonisolated`.

### Tests

1. Known-string count matches the daemon's count for the same string (fixture).
2. `estimated` flag semantics: measured counts report `estimated: false` on SDK 27.
3. Missing input → `INVALID_PARAMS` with populated NSError userInfo (0.3).
4. Session-transcript counting (if daemon supports) parity.

On-device smoke equivalent: covered by `scripts/smoke/textgen.mjs` (context
policy / overflow checks).

### Acceptance criteria

- [ ] Method exists with the exact signature; result byte-parity with daemon fixtures.
- [ ] Error contract (0.3) verified for each mapped code.
- [ ] No session side effects.

---

## U3 — `visionOcr(params:)` / `visionBarcode(params:)`

**Goal.** Expose the core's `VisionHandler.swift` (OCR + barcode, EXIF-aware)
in-process, mirroring the daemon's `vision.ocr` / `vision.barcode` methods.

### Proposed Swift API

```swift
extension FoundationModelsBridge {
    /// `params` mirrors the daemon's `foundationmodels.vision.ocr` params:
    /// inline `base64` + `mimeType`, or allowlisted `path`; EXIF orientation
    /// is honored by the core.
    public func visionOcr(params: [String: Any]) async throws -> [String: Any]

    /// Same input contract as `visionOcr`; returns barcode observations in
    /// the daemon's result shape.
    public func visionBarcode(params: [String: Any]) async throws -> [String: Any]
}
```

Plugin callsites: `try await bridge.visionOcr(params: params)` and
`try await bridge.visionBarcode(params: params)` — exact match.

### Semantics

- Results are byte-identical to the daemon's `vision.ocr` / `vision.barcode`
  results (recognized text blocks / barcode payloads with the daemon's field
  names).
- Image inputs follow the daemon's multimodal rules: `base64`+`mimeType`
  inline, or filesystem `path` subject to the same allowlist policy
  (fail-closed when no allowlist is configured); EXIF orientation applied
  before analysis (handled by `VisionHandler`).
- These are analysis primitives, distinct from native tools (U7): they do not
  create sessions and never invoke the language model.

### Error mapping

| Condition | `data.code` |
|---|---|
| OCR unavailable on this OS/device | `VISION_OCR_UNAVAILABLE` |
| Barcode scanning unavailable | `VISION_BARCODE_UNAVAILABLE` |
| Missing/undecodable image (bad base64, unsupported mime) | `INVALID_PARAMS` or `MULTIMODAL_INPUT_UNAVAILABLE` — match daemon per case |
| Path rejected by allowlist | daemon's allowlist violation code (parity) |

### Implementation notes

- Straight delegation to `FoundationModelsCore/VisionHandler.swift` — the same
  instance/path the daemon uses. No image decoding logic in the bridge.
- Both methods `async throws`, `nonisolated`.

### Tests

1. Fixture image with known text → OCR result matches daemon output byte-for-byte.
2. EXIF-rotated fixture → same result as the unrotated equivalent.
3. Fixture barcode (QR) → payload matches daemon fixture.
4. Bad base64 / missing image → typed error per table, NSError userInfo populated.
5. Path outside allowlist → fail-closed typed error.

On-device smoke equivalent: `scripts/smoke/vision.mjs`.

### Acceptance criteria

- [ ] Both methods exist with exact signatures; daemon byte-parity on fixtures.
- [ ] EXIF awareness verified by test 2.
- [ ] Unavailable-path codes (`VISION_*_UNAVAILABLE`) emitted correctly.

---

## U4 — `logFeedbackAttachment(params:)`

**Goal.** Expose `LanguageModelSession.logFeedbackAttachment(sentiment:issues:
desiredResponseText:)` in-process, mirroring the daemon's
`foundationmodels.feedback.logAttachment`.

### Proposed Swift API

```swift
extension FoundationModelsBridge {
    /// `params` mirrors the daemon's `feedback.logAttachment` params:
    /// `sessionId`, `sentiment` ("positive" | "negative"), optional
    /// `issues`, optional `desiredResponseText`.
    public func logFeedbackAttachment(params: [String: Any]) async throws -> [String: Any]
}
```

Plugin callsite: `try await bridge.logFeedbackAttachment(params: params)` — exact match.

### Semantics

- Attaches feedback to the named session's underlying
  `LanguageModelSession`; result shape matches the daemon (`{"ok": true, ...}`).
- Unknown/expired `sessionId` fails with the daemon's session-not-found code.
- Does not mutate the transcript; does not trigger generation.

### Error mapping

| Condition | `data.code` |
|---|---|
| Feedback attachments unsupported (OS/device) | `FEEDBACK_ATTACHMENT_UNAVAILABLE` |
| Missing `sessionId`/`sentiment`, invalid sentiment value | `INVALID_PARAMS` |
| Unknown/expired session | daemon's session-not-found code (parity) |

### Implementation notes

- Delegates to the daemon-equivalent core call through `SessionRegistry`
  lookup. TTL/LRU eviction (30 min / 256 entries) applies as usual — an evicted
  session is "unknown".

### Tests

1. Positive + negative sentiment with `issues` and `desiredResponseText` → ok result.
2. Unsupported environment → `FEEDBACK_ATTACHMENT_UNAVAILABLE`.
3. Missing/invalid params → `INVALID_PARAMS`.
4. Unknown session → typed error.

On-device smoke equivalent: extend `scripts/smoke/textgen.mjs` or a dedicated
feedback smoke mirroring the daemon's.

### Acceptance criteria

- [ ] Method exists with exact signature; result parity with daemon.
- [ ] All mapped error codes verified.

---

## U5 — Session lifecycle: `history` in `createSession`, `transitionSession`, `prewarm`

**Goal.** Bring the bridge's session surface to parity with the daemon's
`sessions.create` (including transcript seeding via `history`),
`sessions.transition` (instructions change preserving transcript), and
`sessions.prewarm`.

### Proposed Swift API

```swift
extension FoundationModelsBridge {
    /// EXISTING signature — kept source-compatible:
    ///   func createSession(config: [String: Any]) -> [String: Any]
    /// Extension: `config` now also accepts `history` — an array of
    /// daemon-shaped transcript entries, seeded via
    /// `LanguageModelSession(model:tools:transcript:)`.
    ///
    /// DIVERGENCE NOTE: the current method is synchronous and non-throwing,
    /// and the Flutter plugin calls it without `try`. Keep that shape:
    /// malformed `history` entries do NOT fail at create time; the failure
    /// surfaces at the first respond/stream with
    /// `UNSUPPORTED_TRANSCRIPT_CONTENT`, matching the daemon's lazy
    /// session-materialization semantics. (If upstream prefers fail-fast,
    /// make it `throws` and adjust the plugin's `sessionCreate` callsite to
    /// `do/catch` + `Self.flutterError(from:)`.)

    /// Changes a session's instructions while preserving its transcript,
    /// mirroring the daemon's `sessions.transition`.
    /// `params`: `sessionId`, `instructions`, optional `options`.
    public func transitionSession(params: [String: Any]) async throws -> [String: Any]

    /// Prewarms a session via `LanguageModelSession.prewarm(promptPrefix:)`,
    /// mirroring the daemon's `sessions.prewarm`.
    /// `params`: `sessionId`, optional `promptPrefix`.
    public func prewarm(params: [String: Any]) async throws -> [String: Any]
}
```

Plugin callsites: `try await bridge.transitionSession(params: params)` and
`try await bridge.prewarm(params: params)` — exact match. `createSession` is
already called as `bridge.createSession(config: params)`; only the accepted
config keys change.

### Semantics

- **`history` seeding.** Each entry is validated against the daemon's
  transcript-entry schema; the resulting `Transcript` is passed to
  `LanguageModelSession(model:tools:transcript:)`. Unsupported entry types
  (including `.reasoning`, which the wire does not expose) fail with
  `UNSUPPORTED_TRANSCRIPT_CONTENT` at first use.
- **First-request-wins.** `instructions` supplied in a later
  respond/stream against an existing session are ignored; changing
  instructions requires `transitionSession` (preserves transcript),
  re-`createSession` with the same id, or dispose+recreate (blank
  transcript). This is daemon semantics and must be documented in the
  method docstring — it is the number-one consumer pitfall.
- **`transitionSession`** atomically swaps instructions on the live session;
  it fails if a generation is in flight on that session
  (`TRANSCRIPT_MUTATION_WHILE_RESPONDING` / `SESSION_BUSY`, match the
  daemon's choice per case).
- **`prewarm`** calls `LanguageModelSession.prewarm(promptPrefix:)`;
  `promptPrefix` defaults per the daemon (absent → instructions/system
  prefix). Result shape matches the daemon (`{"ok": true, ...}`).
- Registry behavior unchanged: TTL 30 min, LRU 256 (`SessionRegistry`).

### Error mapping

| Condition | `data.code` |
|---|---|
| Unsupported/invalid `history` entry | `UNSUPPORTED_TRANSCRIPT_CONTENT` |
| Missing `sessionId` (transition/prewarm) | `INVALID_PARAMS` |
| Unknown/expired session | daemon's session-not-found code (parity) |
| Transition during active generation | `TRANSCRIPT_MUTATION_WHILE_RESPONDING` / `SESSION_BUSY` (daemon parity) |
| Model unavailable at materialization | `APPLE_MODEL_UNAVAILABLE` (+`reasonCode`) |

### Implementation notes

- Reuse `SessionRegistry` and the daemon handlers for
  `sessions.create/transition/prewarm` as the blueprint; the transcript
  decoding helper the daemon uses for `history` must be shared, not copied.
- `transitionSession`/`prewarm` coordinate with the U1/U6 generation
  registry to detect in-flight generations on the session.

### Tests

1. Create with `history` → first respond recalls the seeded transcript
   (echo test, mirroring the daemon's history test).
2. Invalid entry type in `history` → `UNSUPPORTED_TRANSCRIPT_CONTENT` at
   first respond.
3. Second `instructions` on an existing session is ignored
   (first-request-wins).
4. `transitionSession` → new instructions honored, transcript preserved
   (recall test after transition).
5. Transition during active stream → typed error.
6. `prewarm` → ok result; session still functional afterwards.
7. TTL/LRU behavior unchanged (existing registry tests stay green).

On-device smoke equivalents: `scripts/smoke/textgen.mjs` (session recall,
instructions) and the daemon's sessions smoke.

### Acceptance criteria

- [ ] `createSession` accepts `history` without breaking the existing sync signature.
- [ ] `transitionSession` and `prewarm` exist with exact signatures and daemon parity.
- [ ] First-request-wins documented and tested.

---

## U6 — `cancelGeneration(generationId:)` — cooperative cancellation

**Goal.** In-process equivalent of the daemon's `generation.cancel`:
cooperative, idempotent cancellation of a streaming generation by its
correlation id.

### Proposed Swift API

```swift
extension FoundationModelsBridge {
    /// Cancels the streaming generation registered under `generationId`.
    ///
    /// - Idempotent: repeated calls, and calls for unknown/finished ids,
    ///   are no-ops.
    /// - Thread-safe: callable from any thread/queue (the Flutter plugin
    ///   calls it from the platform thread and from an EventChannel
    ///   `onCancel` callback).
    /// - Effect: the underlying streaming `Task` is cancelled; the stream
    ///   terminates with an `error` event whose `data.code` is
    ///   `GENERATION_CANCELLED` (see U1 terminal rule).
    public func cancelGeneration(generationId: String)
}
```

Plugin callsites: `bridge.cancelGeneration(generationId:)` in the
`generation.cancel` route, and in `StreamEventHandler.onCancel` for implicit
cancel on stream abandon (analogous to the daemon's client-EOF semantics) —
exact match.

### Semantics

- **Scope (documented verbatim in the docstring):** only streaming
  generations are interruptible. Cancelling a unary `respond` is not
  supported and does not stop native generation; do not read "cancellation
  is reachable from the API" as "every operation is interruptible".
- **Cancel-before-first-delta:** stream emits no content events, terminates
  with `error`/`GENERATION_CANCELLED` (see U1).
- **Implicit cancel:** consumer-side stream abandonment maps to an explicit
  `cancelGeneration` call (the plugin does this); the bridge itself has no
  abandonment detection duty, but MUST tolerate cancel races with natural
  completion (no-op, no crash).
- **Registry:** the `generationId → Task` registry introduced in U1 owns
  cancellation; removal happens on terminal event or cancel, whichever
  first, exactly once.

### Error mapping

`cancelGeneration` itself never fails (Void, idempotent). The *stream*
surfaces `GENERATION_CANCELLED` per U1. A cancel arriving for an already-
completed generation is a silent no-op.

### Implementation notes

- Reuse the daemon's cooperative-cancellation pattern for `streamResponse`
  (`Task.cancel()` + cancellation checks in the delta loop); the core's
  streaming engine must check `Task.isCancelled` between deltas.
- Registry guarded by `NSLock` or an actor; `cancelGeneration` is
  synchronous and must not block on generation teardown — cancel and return.
- Swift 6: the registry state is shared across executors; use the same
  synchronization pattern already present in the bridge.

### Tests

1. Start stream, cancel after N deltas → terminal `error` event with
   `GENERATION_CANCELLED`; no `done`; no further deltas.
2. Cancel before first delta → lifecycle rule per U1.
3. Double cancel / cancel after `done` / cancel unknown id → no-ops, no
   crash, no extra events.
4. Cancel one of two concurrent generations → only the target terminates.
5. Threading: cancel from a different queue than the streaming task.

On-device smoke equivalent: `scripts/smoke/streaming.mjs` (cancel case).

### Acceptance criteria

- [ ] Method exists, synchronous, idempotent, thread-safe.
- [ ] Stream always terminates with exactly one `GENERATION_CANCELLED` error event.
- [ ] No crashes/leaks under cancel races (test 3).

---

## U7 — Duplex tool calling: `tool_call_request` events + `submitToolResult(params:)`

**Goal.** In-process equivalent of the daemon's duplex tool protocol:
mid-stream `tool_call_request` events whose completion blocks generation
until the consumer submits `tools.result`. Largest ticket; lands after
streaming (U1/U6) is stable.

### Proposed Swift API

```swift
extension FoundationModelsBridge {
    /// Completes the pending tool call identified by `toolCallId`,
    /// unblocking the native generation that emitted the corresponding
    /// `tool_call_request` event.
    ///
    /// `params` mirrors the daemon's `foundationmodels.tools.result`:
    /// `toolCallId`, and exactly one of `result` (tool output payload) or
    /// `error` (`{"code": ..., "message": ...}`).
    ///
    /// Returns `{"ok": true, ...}` once the result has been delivered to the
    /// waiting generation. Throws for unknown/stale `toolCallId` or
    /// malformed params.
    public func submitToolResult(params: [String: Any]) async throws -> [String: Any]
}
```

No new streaming signature: U1's `respondStream` emits the additional event
types (`tool_call_start`, `tool_call_delta`, `tool_call_request`,
`tool_call_result`) when `tools` are present.

Plugin callsite: `try await bridge.submitToolResult(params: params)` — exact
match.

### Semantics

- **Stream-only.** Callback tools are rejected on unary paths:
  `respond(params:)` with callback tools throws
  `TOOL_CALLBACKS_REQUIRE_STREAMING`.
- **Request-scoped.** Tool definitions travel in the stream params; they are
  never persisted on the session. A new stream re-declares its tools.
- **Blocking contract.** When the model requests a callback tool, the bridge
  emits `tool_call_request` (`requestId`, `toolCallId`, tool name, arguments)
  and **blocks the generation** until `submitToolResult` delivers a
  `result` or `error` for that `toolCallId` — the in-process equivalent of
  the daemon's "block until tools.result arrives on the same connection".
- **Callback failure.** An `error` submitted for a tool call aborts the
  generation with a terminal `error` event:
  `TOOL_EXECUTION_FAILED` with `toolName` and `callbackCode`
  (`TOOL_CALLBACK_ERROR`, `TOOL_CALLBACK_NOT_FOUND`, ...) in `data`,
  mirroring the daemon.
- **Multiple/sequential calls** within one stream follow the daemon's
  sequencing (tool_call_request → result → generation resumes; possibly
  more calls; then content/`done`).
- **Cancellation interaction (U6):** cancelling a generation that is blocked
  awaiting a tool result unblocks it and terminates the stream with
  `GENERATION_CANCELLED`; a late `submitToolResult` for that `toolCallId`
  then throws (stale id).
- **Native tools** (`{"native": "ocr"}`, `{"native": "barcode"}`) execute
  in-process via `VisionHandler` with no callback round-trip; they are
  allowed on unary `respond` and require the input image to carry a `label`
  (attachment label / ImageReference), matching the daemon.
- **Static tools** (`staticOutput`) need none of this machinery and already
  work wherever tools are accepted.

### Error mapping

| Condition | Surface | `data.code` |
|---|---|---|
| Callback tools on `respond`/non-stream path | throw | `TOOL_CALLBACKS_REQUIRE_STREAMING` |
| Callback returned error | terminal `error` event | `TOOL_EXECUTION_FAILED` (+`toolName`, `callbackCode`) |
| `submitToolResult` with unknown/stale `toolCallId` | throw | daemon's not-found code for tool results (parity) |
| Missing `toolCallId`, or neither/both of `result`/`error` | throw | `INVALID_PARAMS` |
| Unsupported system tool | throw | `SYSTEM_TOOL_UNAVAILABLE` |
| Cancel while awaiting tool result | terminal `error` event | `GENERATION_CANCELLED` |

### Implementation notes

- Blueprint: the daemon's socket-scoped tool bridge — re-scope from
  "socket connection" to "in-process completer". Maintain a
  `toolCallId → CheckedContinuation` (or AsyncThrowingStream-based
  completer) registry, populated when `tool_call_request` is emitted and
  consumed by `submitToolResult`.
- The core tool-calling engine already drives
  `tool_call_start/delta/result` assembly; the bridge supplies the
  "execute callback tool" closure that suspends on the completer.
- All registries must be cancellation-safe: continuation resumed exactly
  once (use `CheckedContinuation` and audit with runtime checks in debug).
- Swift 6: continuations and registries cross actors; keep payloads value-
  typed.

### Tests

1. Happy path: stream with one callback tool → `tool_call_request` observed;
   `submitToolResult(result:)` → generation resumes; `tool_call_result` +
   content + `done` observed.
2. Callback error: `submitToolResult(error:)` → terminal
   `TOOL_EXECUTION_FAILED` with `toolName`/`callbackCode`; no `done`.
3. Unary `respond` with callback tools → `TOOL_CALLBACKS_REQUIRE_STREAMING`.
4. Stale `toolCallId` (after completion/cancel) → typed throw.
5. Cancel while blocked on tool result → `GENERATION_CANCELLED`; late
   submit throws.
6. Sequential multi-call stream completes in order.
7. Native OCR/barcode tools work on unary `respond` with labelled image;
   missing label → typed error (daemon parity).

On-device smoke equivalent: `scripts/smoke/toolcalling.mjs`.

### Acceptance criteria

- [ ] `submitToolResult` exists with exact signature; blocking contract honored.
- [ ] All event types and error codes in the mapping verified.
- [ ] Cancel/completion races covered by tests 4–5.
- [ ] Toolcalling smoke passes on device.

---

## U8 — MLX / CoreAI backend exposure (`apple.mlx:*`, `apple.coreai:*`)

**Goal.** Let bridge consumers select the MLX and CoreAI inference backends
already implemented in the core (`MLXInferenceBackend.swift`,
`CoreAIInferenceBackend.swift`, `CoreAIModelRegistry.swift`) by passing the
daemon's model ids (`apple.mlx:*`, `apple.coreai:*`) through the existing
`model` param.

### Proposed Swift API

No new methods. The change is behavioral, across the existing and new
surface:

```swift
// createSession(config:) / respond(params:) / respondStream(params:onEvent:)
// now accept params["model"] = "apple.mlx:<name>" | "apple.coreai:<name>"
// and route to the corresponding core backend.
//
// availability() and capabilities() are extended to report the backends'
// real state (see Integration Contract, section 9).
```

There is no plugin callsite to adjust: the Flutter envelope already forwards
`model` verbatim, and feature-detection flows through
`capabilities()`/`availability()`.

### Semantics

- **Model resolution.** `apple.mlx:*` resolves through the MLX backend's
  model registry; `apple.coreai:*` resolves through `CoreAIModelRegistry`.
  Unknown/unregistered/unready model → `APPLE_MODEL_UNAVAILABLE` with the
  backend-appropriate `reasonCode`, never a silent fallback to the system
  model (offline/no-silent-fallback invariant).
- **Direct-path restrictions (daemon parity, current behavior):** MLX/CoreAI
  generations reject `tools` and `contextOptions` with `UNSUPPORTED_OPTION`
  until the core lifts those restrictions; the rejection must name the
  offending option in `data`.
- **Default model unchanged.** Absent `model` (or `apple.system`) keeps the
  existing `SystemLanguageModel` path; U8 is purely additive.
- **Streaming.** `respondStream` supports MLX/CoreAI models with the same
  v2 event contract as U1 (subject to the direct-path restrictions above).
- **Sessions.** Session semantics (first-request-wins, TTL/LRU) apply
  identically for backend sessions if the core materializes them through
  `SessionRegistry`; if the core treats direct paths as sessionless,
  `sessionId` with an MLX/CoreAI model fails with `UNSUPPORTED_OPTION` —
  match whatever the daemon does today, and document the choice in
  `capabilities()`.

### Error mapping

| Condition | `data.code` |
|---|---|
| Model id unknown / not registered / assets not ready | `APPLE_MODEL_UNAVAILABLE` (+`reasonCode`) |
| `tools` or `contextOptions` on a direct path | `UNSUPPORTED_OPTION` (names the option) |
| Backend inference timeout | `MODEL_TIMEOUT` |
| Backend-specific load/runtime failure | `UNKNOWN_MODEL_ERROR` with backend detail in `data` — or the daemon's specific code if one exists (parity first) |

### Implementation notes

- Zero new inference logic: resolution and execution already live in
  `MLXInferenceBackend.swift`, `CoreAIInferenceBackend.swift`, and
  `CoreAIModelRegistry.swift`; the daemon's model-dispatch code is the
  blueprint for routing on the `model` prefix.
- Surface work only: parse `params["model"]`, route, and extend
  `availability()`/`capabilities()` payloads.
- Keep params byte-compatible with the daemon for these model ids.

### Tests

1. `respond` with a registered `apple.mlx:*` model returns text (unit-level
   with the core's fixture/mock backend if the daemon tests have one).
2. Unregistered model id → `APPLE_MODEL_UNAVAILABLE` with stable
   `reasonCode`.
3. `tools` / `contextOptions` on a direct path → `UNSUPPORTED_OPTION`
   naming the option.
4. Absent `model` → system path unaffected (regression).
5. `capabilities()` reports backend availability truthfully on a host
   without MLX/CoreAI assets.

On-device smoke equivalents: `scripts/smoke/textgen.mjs` run with
`model=apple.mlx:*` / `apple.coreai:*` on a host with the assets.

### Acceptance criteria

- [ ] Both model-id families route to the correct core backend.
- [ ] Direct-path restrictions enforced with `UNSUPPORTED_OPTION`, daemon parity.
- [ ] No silent fallback to the system model.
- [ ] `capabilities()`/`availability()` reflect real backend state.

---

## U9 — PCC inference in an entitled build

**Goal.** Enable Private Cloud Compute inference in-process when the host
binary is signed with `com.apple.developer.private-cloud-compute`.
Availability/quota introspection already exists in the core; inference is
gated by the Apple-granted entitlement. This ticket is **gated**: it cannot
be completed or fully validated without the entitlement.

### Proposed Swift API

No new methods. PCC selection flows through existing params (the daemon's
PCC-related options/keys, e.g. model/option selection per `protocol.md`),
and failures surface through the existing error contract:

```swift
// respond(params:) / respondStream(params:onEvent:) honor the daemon's
// PCC selection keys when, and only when, the process is entitled.
// availability()/capabilities() report PCC state (available, quota) in
// all builds, entitled or not.
```

No plugin callsite changes: the Flutter plugin inherits PCC transparently
once the core/bridge supports it; the Flutter app itself would need to be
signed with the entitlement for in-process PCC to engage.

### Semantics

- **Gating.** In non-entitled builds the behavior is byte-identical to
  today: PCC-dependent requests fail with `PCC_UNAVAILABLE`; nothing else
  changes. Entitlement presence is detected at runtime; never assume it at
  compile time.
- **Entitled build.** PCC-eligible requests route per the core's existing
  PCC path; quota exhaustion and unavailability surface as typed errors
  (below). No silent downgrade from a requested PCC path to on-device
  execution, and no silent upgrade from on-device to PCC — the
  offline/no-silent-fallback invariant applies in both directions.
- **Introspection for all builds.** `availability()`/`capabilities()`
  expose PCC availability, entitlement presence, and quota state so
  consumers can feature-detect without attempting inference.

### Error mapping

| Condition | `data.code` |
|---|---|
| PCC requested without entitlement / service unavailable | `PCC_UNAVAILABLE` (+`pccFailureKind`, `retryable`) |
| Quota exhausted | `PCC_QUOTA_EXHAUSTED` (+`pccFailureKind`, `retryable`) |
| PCC request timeout | `MODEL_TIMEOUT` |

### Implementation notes

- Reuse the core's existing availability/quota surfaces; the bridge adds
  only param plumbing and `capabilities()` reporting.
- Keep the entitled code path behind runtime entitlement checks so a single
  source tree serves both build flavors; build configuration (entitlements
  file, signing notes) lives with the ios-bridge target, documented inline.
- Coordinate with the core owner before landing: the PCC inference path in
  the core may itself be entitlement-gated upstream.

### Tests

1. Non-entitled build: PCC request → `PCC_UNAVAILABLE`; everything else
   regression-green (this is the only test runnable without the
   entitlement).
2. `capabilities()` reports entitlement/quota state truthfully in a
   non-entitled build.
3. (Entitlement-gated, manual/on-device): PCC inference returns a
   completion; quota exhaustion maps to `PCC_QUOTA_EXHAUSTED`.

On-device smoke equivalent: PCC variants of `scripts/smoke/textgen.mjs` /
`streaming.mjs`, run only on entitled builds.

### Acceptance criteria

- [ ] Non-entitled behavior unchanged and fully tested (regression).
- [ ] PCC state visible in `capabilities()`/`availability()` in all builds.
- [ ] Entitled path implemented behind runtime checks; validated when the
      entitlement is granted (recorded with date/build in parity docs).
- [ ] No silent fallback in either direction.

---

## 8. Implementation order and rough estimates

Order optimizes for unblocking the Flutter adapter's phases (streaming
first; sessions; surface; tools; gated backends last) and for landing
smaller tickets while larger ones are in review.

| Order | Ticket(s) | Why here | Rough effort |
|---|---|---|---|
| 1 | **U1 + U6** (streaming + cancellation) | Hard dependency of everything streamed (U7 events build on U1; U6 owns the generation registry U7 also uses). Unlocks Flutter phase 2. | Medium + Medium (~1–2 weeks combined, incl. registry + cancel plumbing) |
| 2 | **U5** (session lifecycle) | Self-contained; unblocks `history`/transition/prewarm consumers; registry coordination with U1/U6 now exists. | Low (~2–4 days) |
| 3 | **U2, U3, U4** (surface) | Independent, thin delegations to existing core handlers; good parallel/review-filler tickets. | Low each (~1–2 days each) |
| 4 | **U7** (duplex tools) | Largest design surface (blocking completer registry, cancel races); needs U1/U6 stable. | High (~2–3 weeks) |
| 5 | **U8** (MLX/CoreAI exposure) | Additive routing + capabilities reporting; no consumer is blocked before tools land. | Medium (~1 week) |
| 6 | **U9** (PCC entitled build) | Gated by Apple entitlement; implement scaffolding early if convenient, validate only when granted. | High / schedule-gated |

Cross-cutting: keep the error contract (0.3) and event fixtures (0.4) in a
shared test target from ticket 1 so U2–U9 reuse them.

---

## 9. Integration contract — how the Flutter plugin consumes this surface

This section is the binding agreement between the monorepo (producer) and
the Flutter plugin `foundationmodels_apple` (consumer).

### 9.1 Package consumption

The plugin's SPM manifest (`foundationmodels_apple/ios/Package.swift`)
depends on the Swift packages via the distribution mirror repository
`foundationmodels-swift` (root `Package.swift` exporting products
`FoundationModelsCore` and `FoundationModelsIOSBridge`, synced from this
monorepo and tagged `swift-core/x.y.z`), or — for local development — via a
path override:

```swift
// Manifest is Swift: it may read the environment.
if let local = ProcessInfo.processInfo.environment["FOUNDATIONMODELS_SWIFT_PATH"] {
    deps = [.package(path: local)]           // local monorepo checkout
} else {
    deps = [.package(url: "https://github.com/cristianoaredes/foundationmodels-swift.git",
                     from: "1.0.0")]          // pinned mirror tag
}
```

Consequence for upstream: **the bridge's public API is a published
interface.** Changes to the signatures in this spec require a mirror minor
bump and a coordinated plugin update; additive changes require only a minor
bump.

### 9.2 Feature detection via `capabilities()`

The plugin feature-detects rather than version-sniffing. `capabilities()`
(and where relevant `availability()`) MUST be extended to advertise each
landed extension, so the Dart side can gate API calls and degrade by
`reasonCode`. Proposed additive keys (exact naming may follow the daemon's
existing capabilities payload conventions — daemon parity wins):

```json
{
  "features": {
    "streaming": true,                 // U1
    "generationCancel": true,          // U6
    "countTokens": true,               // U2
    "vision": {"ocr": true, "barcode": true},   // U3
    "feedbackAttachment": true,        // U4
    "sessions": {"history": true, "transition": true, "prewarm": true},  // U5
    "toolCalling": {"duplex": true, "native": ["ocr", "barcode"], "static": true},  // U7
    "backends": {"mlx": true, "coreai": true},  // U8 (truthful per host)
    "pcc": {"entitled": false, "available": false, "quota": null}       // U9
  }
}
```

Rule: a feature flag may be `true` only when the corresponding method is
implemented AND functional on the current host (mirroring the upstream
parity discipline — never report a capability as supported unless it uses
the native Apple API or documents a precise fallback).

### 9.3 Method ↔ bridge-method matrix (consumer callsites)

| Envelope method (`foundationmodels.*`) | Bridge method | Ticket |
|---|---|---|
| `health` / `availability` / `capabilities` | `health()` / `availability()` / `capabilities()` | existing |
| `sessions.create` | `createSession(config:)` (+`history`) | U5 |
| `sessions.respond` | `respond(params:)` | existing (+U7/U8 behavior) |
| `sessions.stream` | `respondStream(params:onEvent:)` | U1 |
| `sessions.dispose` | `disposeSession(sessionId:)` | existing |
| `sessions.transition` | `transitionSession(params:)` | U5 |
| `sessions.prewarm` | `prewarm(params:)` | U5 |
| `context.countTokens` | `countTokens(params:)` | U2 |
| `generation.cancel` | `cancelGeneration(generationId:)` | U6 |
| `tools.result` | `submitToolResult(params:)` | U7 |
| `vision.ocr` / `vision.barcode` | `visionOcr(params:)` / `visionBarcode(params:)` | U3 |
| `feedback.logAttachment` | `logFeedbackAttachment(params:)` | U4 |

### 9.4 Error contract recap (consumer-side)

Unary failures arrive to Dart as
`FlutterError(code: "<jsonRpcCode>", message:, details: errorData)`;
stream failures arrive as terminal `error` events with the same payload
inside. In both cases `errorData.code` (the stable machine string) is the
contract Dart maps to typed exceptions. This holds only if every bridge
throw conforms to section 0.3 and every terminal `error` event carries the
daemon-shaped `error` payload — both are tested per ticket.

### 9.5 Known divergences between the written plugin and this spec

Recorded for whoever reconciles the two repos:

1. **`createSession` stays sync/non-throwing** (U5): the plugin calls it
   without `try`. Invalid `history` therefore fails lazily at first
   respond/stream with `UNSUPPORTED_TRANSCRIPT_CONTENT`. If upstream makes
   it `throws`, the plugin's `sessionCreate` callsite must gain a
   `do/catch` mapping to `Self.flutterError(from:)`.
2. **`requestId` enrichment:** the plugin fills `requestId` on stream
   events when absent; this spec asks the bridge to always set it (U1
   semantics). The plugin's fallback stays harmless; no change required.
3. **Unknown-session error code:** the plugin has no callsite expectation
   beyond the generic 0.3 contract; this spec defers to "whatever the
   daemon emits today" rather than naming a code. When the daemon's exact
   code is confirmed in `docs/protocol.md`, pin it in U1/U4/U5 error
   tables (search-and-replace "session-not-found code (parity)").
4. **U8/U9 have no plugin callsites:** exposure is purely via existing
   `model`/option params plus `capabilities()` reporting. Any future
   dedicated Dart API for PCC/backend selection will feature-detect on the
   flags in 9.2.

---

## Appendix A — Plugin callsite reference (verbatim signatures the plugin compiles against)

From `FoundationModelsPlugin.swift` (target contract; file header notes
these will not compile against the current bridge until U1–U7 land):

```swift
try await bridge.countTokens(params: params)                 // U2
bridge.createSession(config: params)                         // U5 (extended config)
try await bridge.transitionSession(params: params)           // U5
try await bridge.prewarm(params: params)                     // U5
bridge.cancelGeneration(generationId: generationId)          // U6 (2 callsites:
                                                             //  route + stream abandon)
try await bridge.submitToolResult(params: params)            // U7
try await bridge.visionOcr(params: params)                   // U3
try await bridge.visionBarcode(params: params)               // U3
try await bridge.logFeedbackAttachment(params: params)       // U4
try await FoundationModelsBridge.shared.respondStream(
    params: params
) { event in /* [String: Any] -> Void */ }                   // U1
```

Streaming correlation rule implemented by the plugin (bridge must honor the
same id in events): `generationId = params["generationId"] ?? envelope.id`.
