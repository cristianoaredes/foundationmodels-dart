# Phase 2 — Streaming end-to-end

Implementation spec for ADR-0001 §16 phase 2 ("Streaming"). Read ADR-0001
first; this document is the single source of work for the phase. All type and
file references point at the real repository state after phases 0–1.

## Goal

Native streaming works end-to-end on device: `FmSession.stream(...)` emits
typed `FmStreamEvent`s produced by the Swift core via upstream ticket U1
(`respondStream(params:onEvent:)`), and cooperative cancellation (U6) works
from both the explicit `CancelToken` path and the implicit
subscription-abandon path, surfacing typed `GenerationCancelledException`s.
Mid-stream failures surface as the correct typed
`FoundationModelsException` subtypes on the stream, never silently.

The channel plumbing already exists — the EventChannel
(`foundationmodels/streams`, `kEventChannelName` in
`packages/foundationmodels_apple/lib/src/apple_rpc_transport.dart`), the
Swift `StreamEventHandler` (register/unregister/emit, implicit cancel in
`onCancel`), and the requestId demultiplexer in `TransportProvider.stream`
(`packages/foundationmodels/lib/src/transport_provider.dart`). Phase 2 is
contract validation, edge-case hardening, and on-device evidence — not new
plumbing.

## Depends on

- Phase 0 (spike): envelope routing + unary `respond` on device.
- Phase 1 (core Dart): sealed `FmStreamEvent` hierarchy and
  `FmStreamEvent.fromMap` (`packages/foundationmodels_platform_interface/lib/src/events.dart`),
  `CancelToken`/`CancelTokenSource` (`packages/foundationmodels/lib/src/cancel.dart`),
  `TransportProvider` demux + `cancelGeneration`, `MockProvider.stream`
  deterministic event sequence.
- Upstream tickets: **U1** (`respondStream(params:onEvent:)` on
  `FoundationModelsBridge`) and **U6** (`cancelGeneration(generationId:)`,
  idempotent). The Swift plugin code is already written against these target
  signatures (`FoundationModelsPlugin.startStreaming`,
  `RPCMethod.generationCancel`); it compiles only once U1/U6 land.

## Scope

### In

- Validate the stream-event wire contract against the real core (event types,
  field names, ordering, correlation ids) and reconcile any mismatch.
- Reconcile the `error` event payload shape between the Swift emitter and the
  Dart parser (known divergence — see work item 1).
- Cancellation: mid-stream via `CancelToken`; before the first delta; repeated
  cancels (idempotent); implicit cancel on subscription abandon
  (`StreamController.onCancel` in `TransportProvider.stream` and the Swift
  `StreamEventHandler.onCancel`).
- Mid-stream errors: `GENERATION_CANCELLED`, `TOOL_EXECUTION_FAILED`, and any
  other `error.data.code` arrive as an `error` event and are surfaced via
  `StreamError.toException()` as the typed exception from
  `FoundationModelsException.fromError`.
- Structured streaming: `structured_delta` accumulation, `done` with `usage`,
  session materialization on first event.
- On-device smokes: `streaming`, `sessions`, `instructions`, `sampling`.

### Out

- Tool calling events (`tool_call_*`) beyond parsing them through — full
  duplex tool execution is phase 4.
- `ContextPolicy.compact` (stub stays; see phase 3 spec).
- Per-call client-side timeouts (ADR-0001 §6 mentions them; currently
  unimplemented — tracked as a gap, see phase 3 spec work item for runtime
  hardening).

## API deltas

No new public API. Phase 2 hardens existing members:

- `FmSession.stream({input, instructions, options, schema, cancelToken})` —
  `packages/foundationmodels/lib/src/session.dart`. Behavior contract, now
  verified on device: terminates with `StreamDone`; failures arrive as typed
  exceptions on the stream; cancelling `cancelToken` sends
  `foundationmodels.generation.cancel` with `generationId == requestId`.
- `TransportProvider.cancelGeneration(String requestId)` — already sends
  `{"method": "foundationmodels.generation.cancel", "params": {"generationId": requestId}}`;
  unchanged.
- Wire-contract fix (not an API change): the canonical `error` event shape is
  defined as **flat**: `{"type": "error", "requestId": ..., "sessionId": ?,
  "traceId": ?, "code": <stable machine string>, "message": ..., "data": {...}?}`
  — exactly what `FmStreamEvent.fromMap` already parses. The Swift emitter and
  the malformed-payload fallback in `MethodChannelFoundationModels.streamEvents`
  are aligned to it.

## Work items

1. **Reconcile the `error` event wire shape.** `FoundationModelsPlugin.startStreaming`'s
   catch block currently emits `{"type": "error", "requestId": ..., "error": {"jsonRpcCode": ..., "message": ..., "data": ...}}`
   (nested), while `StreamError` in `events.dart` reads top-level
   `code`/`message`/`data`. Adopt the flat shape as canonical (it matches
   `FmStreamEvent.fromMap` and the daemon's "events carry the error payload
   fields" semantics): change the Swift catch to emit
   `{"type": "error", "requestId": generationId, "code": <data.code>,
   "message": ..., "data": <error.data>}`; change the malformed-event fallback
   in `apple_rpc_transport.dart` to the same flat shape. Add a contract test
   pinning that a nested `error` map is *not* produced anymore and that a flat
   `GENERATION_CANCELLED` event maps to `GenerationCancelledException`.
2. **Golden event-sequence fixtures.** Extract request/response/event fixtures
   from upstream `docs/protocol.md` into
   `packages/foundationmodels/test/fixtures/` (JSON). Assert with a fake
   `FoundationModelsTransport` that: event order is
   `run_started` → `message_start` → N×`text_delta` → `message_end` → `done`
   (and `structured_delta` in place of `text_delta` when a schema is set);
   every event carries `requestId`; `sessionId`/`traceId` are propagated into
   the typed events when present; unknown event types surface as
   `FormatException` (current `fromMap` behavior — keep, and document).
3. **U1 integration (Swift).** Once `respondStream(params:onEvent:)` lands on
   the bridge, verify `FoundationModelsPlugin.startStreaming`: registration of
   `generationId` before the task starts, enrichment of events missing
   `requestId`, immediate ack `{"ok": true, "generationId": ..., "streaming": true}`,
   and `StreamEventHandler.unregister` on `done`/`error`. No logic may move
   into the plugin beyond channel ↔ dictionary translation (ADR-0001 §9).
4. **Mid-stream cancel.** From Dart: create a `CancelTokenSource`, start
   `session.stream(...)`, cancel after the first `TextDelta`; assert the
   stream terminates with `GenerationCancelledException` (via
   `StreamError.toException()`), that exactly one
   `foundationmodels.generation.cancel` envelope with
   `generationId == requestId` crossed the transport, and that the native
   streaming Task actually stopped (no further deltas after the cancel ack).
   Repeat the cancel: assert idempotence (no error, no duplicate envelope from
   `CancelTokenSource.cancel`, which is already a no-op on second call).
5. **Cancel before the first delta.** Cancel the token between stream start
   and the first event; assert termination with `GenerationCancelledException`
   and no deltas delivered. On the Swift side this exercises U6 against a Task
   that has not emitted yet — verify the registration is still cleaned up.
6. **Implicit cancel on abandon.** Subscribe to `session.stream(...)`, receive
   one delta, then cancel the `StreamSubscription` without a token. Assert
   `TransportProvider.stream`'s `onCancel` sends the cancel envelope once
   (the `settled` guard prevents double-cancel on the terminal path), and that
   abandoning the *whole* EventChannel subscription triggers the Swift
   `StreamEventHandler.onCancel` implicit cancel of all active generations.
   Keep the invariant in the doc comment of `MethodChannelFoundationModels.streamEvents`:
   `package:foundationmodels` holds exactly one EventChannel subscription.
7. **Mid-stream error mapping.** With a fake transport, emit `error` events
   with codes `GENERATION_CANCELLED` and `TOOL_EXECUTION_FAILED` (the latter
   with `data: {"toolName": "x", "callbackCode": "TOOL_CALLBACK_ERROR"}`)
   mid-stream; assert the stream surfaces `GenerationCancelledException` and
   `ToolExecutionFailedException` respectively, via
   `FoundationModels.streamInSession`'s `controller.addError(event.toException())`.
   Assert `GuardrailViolationException.isRetryable == false` and
   `RateLimitedException.isRetryable == true` survive the stream path
   unchanged (table ADR-0001 §7.3).
8. **Structured streaming.** Stream with `schema: FmSchema.object({...})`:
   assert `StructuredDelta` chunks concatenate into JSON that parses and
   validates against the schema, and `StreamDone.usage` parses into `Usage`
   with `estimated` honored (false only when measured natively, SDK 27).
9. **Session materialization race.** Assert the lazy-session invariant on the
   streaming path: native session materializes on the **first streamed event**
   (`session.markMaterialized()` in `streamInSession`), first-request-wins
   instructions apply, and a stream that errors before any event leaves
   `session.isMaterialized == false` so a retry can still set instructions.
10. **On-device smokes** (`scripts/smoke/`, mirror upstream naming):
    - `streaming`: real deltas are incremental (concatenation grows strictly),
      cancel functional, `GENERATION_CANCELLED` typed.
    - `sessions`: recall across turns (the model remembers prior context),
      `transition` after phase 3; for phase 2, dispose + recreate.
    - `instructions`: first-request-wins — later per-request instructions on a
      materialized session are ignored; document observed behavior.
    - `sampling`: `GenerationOptions(temperature: ..., maximumResponseTokens: ...,
      sampling: TopKSampling(...)/TopPSampling(...)/GreedySampling(...))`
      serialize to the wire shape from `options.dart` `toJson()` and are
      honored by the core (observe output-length cap at minimum).
    Record each smoke result (date, device, OS build, `swift-core` version) in
    `docs/parity.md` and flip `Streaming + cancel` to `supported` on evidence.

## Test plan

### Unit (CI, no Mac)

- Extend `packages/foundationmodels/test/streaming_test.dart` with work items
  4–8 against `MockProvider` (which already honors `cancelGeneration` with a
  `GENERATION_CANCELLED` error event and emits the deterministic
  `run_started → ... → done` sequence).
- Extend `packages/foundationmodels_platform_interface/test/events_test.dart`:
  flat `error` event parsing, `StreamError.toException()` per code, missing
  `requestId` → `FormatException`, unknown `type` → `FormatException`.

### Contract (CI, fake transport)

- A `FakeTransport implements FoundationModelsTransport` replaying recorded
  envelopes + scripted `streamEvents`: assert demux isolation (two concurrent
  streams with different `requestId`s receive only their own events),
  terminal-event cleanup (`settle()` runs once), implicit-cancel single-shot
  (work item 6), and that `invoke` failures during stream start close the
  controller with the typed error (the `catch` in
  `TransportProvider.stream.onListen`).

### On-device smoke (Apple Silicon, iOS 27+ / macOS 27+)

- The four smokes of work item 10 run green on a physical device; results
  logged in `docs/parity.md` with evidence fields. Simulator coverage is
  partial — same caveat as upstream.

## Acceptance criteria

- [ ] `error` events are emitted and parsed in the flat canonical shape on
      both sides; a `GENERATION_CANCELLED` error event yields
      `GenerationCancelledException` on device, not `UnknownModelException`.
- [ ] Golden fixtures pass: event ordering and correlation ids match the
      upstream protocol for text and structured streams.
- [ ] Mid-stream cancel, pre-first-delta cancel, repeated cancel, and
      subscription-abandon implicit cancel all terminate the stream with the
      typed exception and stop the native Task (no trailing deltas).
- [ ] Mid-stream `TOOL_EXECUTION_FAILED` maps to
      `ToolExecutionFailedException` carrying `toolName`/`callbackCode`.
- [ ] Concurrent streams demultiplex correctly by `requestId`.
- [ ] `structured_delta` accumulation round-trips into schema-valid JSON;
      `StreamDone.usage.estimated` is honored.
- [ ] CI green without a Mac (`dart test` in both packages).
- [ ] Smokes `streaming`, `sessions`, `instructions`, `sampling` green on
      device; `docs/parity.md` updated with evidence and
      `Streaming + cancel` marked `supported`.

## Estimate

~1 week (matches ADR-0001 §16), assuming U1/U6 land upstream on schedule.
The wire-shape reconciliation (work item 1) and the on-device evidence runs
are the critical path.
