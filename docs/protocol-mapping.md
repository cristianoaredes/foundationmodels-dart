# Protocol mapping — JSON-RPC ↔ Dart API ↔ Swift bridge

The adapter re-mirrors the upstream daemon protocol (v2) over platform
channels: the same envelope `{id, method, params}` that travels the daemon
socket is the argument of the single `invoke` MethodChannel operation. The
table below maps each wire method to the public Dart surface and to the
(target) Swift bridge handler, with the phase that delivers it (ADR-0001 §16).

| JSON-RPC method (`foundationmodels.*`) | Dart API (`package:foundationmodels`) | Swift bridge handler (`FoundationModelsBridge.shared`) | Phase |
|---|---|---|---|
| `health` | `FoundationModels.health()` | `health()` — exists | 0 |
| `availability` | `FoundationModels.availability()` (typed `reasonCode`) | `availability()` — exists | 0 |
| `capabilities` | `FoundationModels.capabilities()` | `capabilities()` — exists | 0 |
| `sessions.create` | `FoundationModels.createSession(...)` (lazy; native session materializes on first respond/stream) | `createSession(config:)` — exists; `history` support is U5 | 0 / 3 |
| `sessions.respond` | `Session.respond(...)` and the `classify` / `extract` / `rank` / `summarize` primitives | `respond(params:)` — exists (async) | 0 |
| `sessions.stream` | `Session.stream(..., tools:)` → `Stream<StreamEvent>` (+ duplex tool exec) | `respondStream(params:onEvent:)` — **U1** | 2 / 4 |
| `sessions.respond` (tools) | `Session.respond(..., tools:)` static/native only; callbacks throw stream-only | `respond(params:)` + tools array | 4 |
| `sessions.dispose` | `Session.dispose()` | `disposeSession(sessionId:)` — exists | 0 |
| `sessions.transition` | `Session.transition(instructions: ...)` (preserves transcript) | `transitionSession(params:)` — **U5** | 3 |
| `sessions.prewarm` | `Session.prewarm()` | `prewarm(params:)` — **U5** | 3 |
| `context.countTokens` | `FoundationModels.countTokens(...)`; also used by `contextPolicy: guard` | `countTokens(params:)` — **U2** | 3 |
| `generation.cancel` | `CancelToken.cancel()`; implicit on stream-subscription abandon | `cancelGeneration(generationId:)` — **U6** (idempotent) | 2 |
| `tools.result` | Tool callback completion (duplex, stream-only) | `submitToolResult(params:)` — **U7** | 4 |
| `vision.ocr` | `FoundationModels.visionOcr(image: {base64,mimeType\|path})` → wire top-level `base64`/`path` | `visionOcr(params:)` — **U3** | 3 |
| `vision.barcode` | `FoundationModels.visionBarcode(...)` → same Core wire shape | `visionBarcode(params:)` — **U3** | 3 |
| `feedback.logAttachment` | `FoundationModels.logFeedbackAttachment(sessionId: …)` (Core requires session id; `generationId` optional alias) | `logFeedbackAttachment(params:)` — **U4** | 3 |

## Stream events (EventChannel `foundationmodels/streams`)

`run_started` · `message_start` · `text_delta` · `structured_delta` ·
`tool_call_start` · `tool_call_delta` · `tool_call_request` · `tool_call_result` ·
`message_end` · `done` · `error`

Every event carries `requestId` (Dart demultiplexes by it); `sessionId` and
`traceId` are included when available. `done` or `error` closes the
corresponding Dart `StreamController`; the Swift side drops the generation
registration. Sealed event classes live in
`package:foundationmodels_platform_interface`.

## Error mapping

Unary failures are `FlutterError(code: "<jsonRpcCode>", message, details:
errorData)`; stream failures arrive as an `error` event with the same payload
shape. `errorData.code` — the stable machine string (e.g. `CONTEXT_OVERFLOW`,
`GENERATION_CANCELLED`) — is mapped 1:1 to typed Dart exceptions per
ADR-0001 §7.3; unknown/absent codes degrade to the generic
`FoundationModelsException` with `details` preserved. Fail typed, never
silently.
