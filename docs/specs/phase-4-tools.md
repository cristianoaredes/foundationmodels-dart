# Phase 4 — Tool calling (duplex)

Implementation spec for ADR-0001 §16 phase 4 ("Tools"), realizing the design
registered in ADR-0001 §11: static tools, callback tools (stream-only,
duplex), and native tools (OCR/barcode). HITL is explicitly **not** in this
phase (phase 7).

## Goal

Tool calling works end-to-end on device with the daemon's duplex semantics
ported to the in-process transport: the model emits `tool_call_request`
mid-stream; the Dart runtime executes the registered callback and returns the
result via `foundationmodels.tools.result` on the same logical channel; the
native generation blocks on the result and resumes. All upstream policies
hold locally: callback tools require streaming (enforced in Dart before the
channel), tools are request-scoped (never persisted in sessions), callback
failures abort generation with `TOOL_EXECUTION_FAILED` + `callbackCode`, and
tool input schemas are sanitized with `SchemaMode.tool` (out-of-subset
keywords stripped at the edge, structural violations still throw).

## Depends on

- Phase 2 (streaming + cancellation verified; sealed event parsing).
- Phase 3 (multimodal image parts with `label`; `FmProvider` extended).
- Upstream ticket **U7** (`submitToolResult(params:)` on
  `FoundationModelsBridge`; the Swift router case `RPCMethod.toolsResult`
  already exists and targets this signature; native generation blocks per
  `toolCallId` completer — the "block until tools.result arrives" contract).
- Existing pieces: `FmMethods.toolsResult`
  (`platform_interface/lib/src/methods.dart`), `SchemaMode.tool` sanitization
  (`foundationmodels/lib/src/schema.dart`), `ToolCallStart`/`ToolCallDelta`/
  `ToolCallResult` events, `ToolCallbacksRequireStreamingException` and
  `ToolExecutionFailedException` (both in
  `platform_interface/lib/src/errors.dart`), `FmImagePart.label` (phase 3).

## Scope

### In

- `FmTool` definitions with `inputSchema` (serialized with
  `SchemaMode.tool` — sanitizing mode).
- Static tools (`staticOutput`) in both `respond` and `stream`.
- Callback tools: **stream-only**, with local
  `ToolCallbacksRequireStreamingException` enforcement in `respond` before
  any transport call (mirroring the upstream TS provider).
- New stream event `tool_call_request` added to the platform interface (see
  "Known divergence" below) and the full duplex loop:
  `tool_call_request` → Dart callback execution →
  `foundationmodels.tools.result` (`{toolCallId, result}` or
  `{toolCallId, error}`) → generation resumes.
- Failure propagation: callback throw → send error result with code
  `TOOL_CALLBACK_ERROR`; no registered callback for the requested tool →
  `TOOL_CALLBACK_NOT_FOUND`; the core aborts with `TOOL_EXECUTION_FAILED`
  carrying `toolName`/`callbackCode`, surfaced as
  `ToolExecutionFailedException`.
- Native tools (`{"native": "ocr"}`, `{"native": "barcode"}`): execute
  in-process without a Dart callback; available in `respond` too; require an
  image part with `label`.
- Cancellation interplay: cancelling a stream while a tool callback is
  in flight.
- Smoke `toolcalling` on device.

### Out

- HITL approve/edit/reject, interrupts, AG-UI events — phase 7 (agent kit).
- MCP tools — phase 7 (optional layer of the agent kit).
- Tool-result persistence in session transcripts beyond what the core does
  natively (request-scoped tools are never persisted, by contract).

## Known divergence to resolve first

ADR-0001 §11 names the mid-stream event **`tool_call_request`**, but
`FmStreamEvent.fromMap` (`platform_interface/lib/src/events.dart`) does not
parse it — it would throw `FormatException` today. Work item 1 adds a
`ToolCallRequest` event class carrying `requestId`, `toolCallId`, `toolName`,
and the complete decoded `arguments` map (the core emits it once arguments
are complete; `tool_call_start`/`tool_call_delta` remain the incremental
argument-progression events for observers).

## API deltas

```dart
// packages/foundationmodels/lib/src/tools.dart (new)
/// A tool definition. Exactly one behavior: [staticOutput], [callback], or
/// [native]. Request-scoped — tools are passed per call and never persisted
/// in a session (upstream contract).
final class FmTool {
  /// Static tool: the core answers from [staticOutput] without any callback.
  /// Usable in `respond` and `stream`.
  const FmTool.static({
    required this.name,
    required this.description,
    required this.inputSchema,
    required Object? staticOutput,
  });

  /// Callback tool: the Dart [callback] executes on `tool_call_request`.
  /// Stream-only — `respond` rejects with
  /// [ToolCallbacksRequireStreamingException] before the channel.
  const FmTool.callback({
    required this.name,
    required this.description,
    required this.inputSchema,
    required FutureOr<Object?> Function(Map<String, Object?> args) callback,
  });

  /// Native tool executed by the core in-process ("ocr" | "barcode").
  /// Requires an image input part carrying [FmImagePart.label].
  /// Usable in `respond` and `stream`.
  const FmTool.native({required String nativeKind}); // "ocr" | "barcode"

  final String name;
  final String description;

  /// Serialized with `schema.toJson(mode: SchemaMode.tool)` — out-of-subset
  /// keywords (maxLength, pattern, oneOf, ...) are stripped at the edge;
  /// structural violations still throw.
  final FmSchema inputSchema;

  /// Wire form: {"name", "description", "inputSchema", ...} plus one of
  /// {"staticOutput": ...} | {"callback": true} | {"native": "ocr"}.
  Map<String, Object?> toJson();
}

// FoundationModels / FmSession — respond & stream gain:
Future<FmResponse> respond({..., List<FmTool>? tools});
Stream<FmStreamEvent> stream({..., List<FmTool>? tools});

// FmRequest gains:
final List<FmTool>? tools;

// packages/foundationmodels_platform_interface/lib/src/events.dart gains:
/// `tool_call_request` — the model requests execution of a callback tool.
/// Terminal point of argument accumulation: carries the decoded arguments.
final class ToolCallRequest extends FmStreamEvent {
  const ToolCallRequest({required super.requestId, super.sessionId,
      super.traceId, required this.toolCallId, required this.toolName,
      required this.arguments});
  final String toolCallId;
  final String toolName;
  final Map<String, Object?> arguments;
  @override
  String get type => 'tool_call_request';
}
```

`TransportProvider` additions (internal): emit `'tools': [...]` in
`_requestParams` when present; on `ToolCallRequest`, run the callback and
`invoke` `FmMethods.toolsResult` with `{"toolCallId": ..., "result": ...}` or
`{"toolCallId": ..., "error": {"code": "TOOL_CALLBACK_ERROR"|"TOOL_CALLBACK_NOT_FOUND", "message": ...}}`.

## Work items

1. **Add `ToolCallRequest`** to `events.dart` (+ `fromMap` case, tests in
   `events_test.dart`). Decide with upstream whether the daemon emits
   complete arguments on `tool_call_request` or whether the client must
   accumulate `tool_call_delta`s; implement accumulation in the runtime if
   needed (buffer per `toolCallId`, decode on request). Document the choice
   in `docs/protocol-mapping.md`.
2. **`FmTool` + wire serialization.** `toJson()` uses
   `inputSchema.toJson(mode: SchemaMode.tool)`; unit-test that `maxLength`/
   `pattern`/`oneOf` are stripped while empty `enum`/external `$ref` still
   throw (existing schema.dart behavior — pin it for the tool path).
3. **Runtime plumbing.** Thread `tools` through `respond`/`stream` →
   `FmRequest` → `TransportProvider._requestParams`. Mock: static tools echo
   `staticOutput` deterministically; callback tools drive a scripted
   `tool_call_request` → result → resumed generation in tests; mock keeps
   `nativeTools: false` in its feature map.
4. **Local stream-only enforcement.** In `FoundationModels.respond` and
   `FmSession.respond`: if `tools` contains any callback tool, throw
   `ToolCallbacksRequireStreamingException(tools: [names...])` **before** any
   guardContext/provider call. Contract-test that zero envelopes cross the
   transport in this case (mirrors the TS provider's local check).
5. **Duplex execution loop.** In the streaming path
   (`FoundationModels.streamInSession` + `TransportProvider.stream`):
   on `ToolCallRequest`, look up the callback by name; missing → send
   `tools.result` with `TOOL_CALLBACK_NOT_FOUND`; callback throws → send with
   `TOOL_CALLBACK_ERROR` (message only, never stack traces or secrets);
   success → send `result`. Tool events (`ToolCallStart`/`ToolCallDelta`/
   `ToolCallResult`) keep flowing to the consumer for observability. The
   Dart side must not serialize concurrent callback executions for the same
   stream unless the core requires it (default: sequential per stream,
   matching the daemon's socket-scoped tool bridge).
6. **Failure mapping.** Assert on fake transport: core-side
   `TOOL_EXECUTION_FAILED` error event with
   `data: {"toolName": ..., "callbackCode": ...}` surfaces as
   `ToolExecutionFailedException` with both fields populated (already
   implemented in `FoundationModelsException.fromError` — pin with tests).
7. **Native tools.** `FmTool.native` serializes `{"native": "ocr"|"barcode"}`;
   validate locally that a request using a native tool includes at least one
   `FmImagePart` with a non-null `label` (throw `ArgumentError` naming the
   missing label otherwise — fail fast, same spirit as
   `UnsupportedOptionException.options`). Verify on device: OCR native tool
   answers from the labeled image without any Dart callback, in both
   `respond` and `stream`.
8. **Cancellation interplay.** Cancel a stream while its tool callback is
   executing: the cancel envelope goes out immediately, the in-flight
   callback result (if it completes) is still delivered via `tools.result`
   (harmless — the core ignores results for cancelled generations), and the
   stream terminates with `GenerationCancelledException`. Pin with a
   fake-transport test.
9. **Request scoping.** Assert tools never persist: two sequential requests
   on one session, only the first with tools — the second request's envelope
   contains no `tools` key, and a `tool_call_request` for a stale tool name
   is answered `TOOL_CALLBACK_NOT_FOUND`.
10. **Smoke `toolcalling`** on device: static tool in `respond`; callback
    weather-style tool in `stream` (observe `tool_call_request` → result →
    resumed text deltas); callback throwing → `ToolExecutionFailedException`
    with `callbackCode: TOOL_CALLBACK_ERROR`; native OCR tool on a labeled
    image. Record evidence in `docs/parity.md` and flip
    `Tool calling (duplex + native + static)` to `supported`.

## Test plan

### Unit (CI, no Mac)

- `FmTool.toJson` shapes for all three kinds; `SchemaMode.tool` sanitization
  pinned for tool schemas.
- `ToolCallRequest.fromMap` round-trip; unknown-field tolerance.
- Local enforcement: callback tools + `respond` →
  `ToolCallbacksRequireStreamingException` with the offending tool names, no
  transport traffic.
- Mock duplex loop deterministic; request scoping (work item 9).

### Contract (CI, fake transport)

- Full duplex sequence replayed: `text_delta` → `tool_call_start` →
  `tool_call_delta`×N → `tool_call_request` → (Dart sends `tools.result`) →
  `tool_call_result` → `text_delta` → `done`; assert the outgoing
  `tools.result` envelope matches the golden fixture from upstream
  `docs/protocol.md`.
- `TOOL_CALLBACK_ERROR` and `TOOL_CALLBACK_NOT_FOUND` error envelopes match
  fixtures; incoming `TOOL_EXECUTION_FAILED` maps typed.
- Cancel-during-callback (work item 8).

### On-device smoke (Apple Silicon)

- Smoke `toolcalling` per work item 10, green on device with evidence logged.

## Acceptance criteria

- [ ] `tool_call_request` parses into `ToolCallRequest` on all transports;
      no `FormatException` on the tool event family.
- [ ] Tool schemas serialize sanitized (`SchemaMode.tool`); structural
      violations still throw locally.
- [ ] Static tools work in `respond` and `stream` with zero callback wiring.
- [ ] Callback tools in `respond` are rejected locally with
      `ToolCallbacksRequireStreamingException` naming the tools — before any
      transport call.
- [ ] Duplex loop works on device: request → Dart execution →
      `tools.result` → generation resumes and completes with `done`.
- [ ] Callback failure and missing callback produce
      `ToolExecutionFailedException` with `toolName` and the correct
      `callbackCode` (`TOOL_CALLBACK_ERROR` / `TOOL_CALLBACK_NOT_FOUND`).
- [ ] Native OCR/barcode tools run without callbacks, in unary and
      streaming, requiring labeled images.
- [ ] Cancel during an in-flight callback terminates with
      `GenerationCancelledException` and no crash/hang.
- [ ] Tools are request-scoped; nothing persists in the session.
- [ ] CI green without a Mac; smoke `toolcalling` green on device;
      `docs/parity.md` updated.

## Estimate

2–4 weeks (matches ADR-0001 §16), dominated by U7 landing and the duplex
contract validation. Dart-side work items 1–4 are mock-testable immediately.
