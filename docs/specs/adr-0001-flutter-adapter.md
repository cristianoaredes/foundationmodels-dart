# ADR-0001 — FoundationModels Flutter: Dart/Flutter adapter for the Swift core

| | |
|---|---|
| **Status** | Accepted |
| **Date** | 2026-08-09 |
| **Author** | Cristiano Aredes |
| **Scope** | This repository, [`foundationmodels-dart`](../../README.md) (separate from the `foundationmodels-js` monorepo, following the ADR-0009 philosophy; originally drafted as `foundationmodels-flutter`) |
| **License** | AGPL-3.0-only (consistent with the monorepo) |
| **Upstream** | [`cristianoaredes/foundationmodels-js`](https://github.com/cristianoaredes/foundationmodels-js) — `swift/FoundationModelsCore` + `swift/ios-bridge` are the single source of truth (ADR-0002) |

> **Implementation note (2026-08-09):** the phase 0–1 scaffold described in this
> ADR **already exists** in this repository:
> [`packages/foundationmodels`](../../packages/foundationmodels) (public Dart
> API + deterministic mock provider),
> [`packages/foundationmodels_platform_interface`](../../packages/foundationmodels_platform_interface)
> (transport contract, stream events, error mapping), and
> [`packages/foundationmodels_apple`](../../packages/foundationmodels_apple)
> (iOS + macOS plugin skeleton). The executable detail of the upstream bridge
> extensions (tickets U1–U9, §9) is specified in
> [`upstream-ios-bridge-extensions.md`](upstream-ios-bridge-extensions.md).

---

## 1. Context and forces

The `foundationmodels-js` monorepo already solves the hard part of accessing
Apple Foundation Models from non-Swift runtimes:

- **`swift/FoundationModelsCore`** (SPM): text generation, streaming
  (`StreamingDelta`), sessions with 30 min TTL + LRU 256 (`SessionRegistry`),
  guided generation via `DynamicGenerationSchema` (nested object, enum,
  `anyOf`, intra-document `$ref`, nullable `type: ["T","null"]`), multimodal
  (path/base64 with allowlist and EXIF), native `countTokens`, Vision
  OCR/barcode, MLX/CoreAI backends, and the stable error contract
  (`NativeErrorContract`).
- **`swift/ios-bridge`** (`FoundationModelsBridge`, `@objc` singleton): proves
  the core works **in-process** with params dictionaries **identical to the
  daemon JSON-RPC ones** — "the Swift core stays the single source of truth"
  (ADR-0002).
- **`packages/foundationmodels-react-native`**: proves that a third-party host
  is a thin adapter (~40 lines of Swift) on top of the ios-bridge.

Forces:

- Flutter is the **third adapter** — same role as the daemon (transport) and
  the RN module (host), without changing the core.
- Flutter serializes `Map<String, Object?>` natively on platform channels
  (StandardMessageCodec) — the "daemon-shaped params" wire format crosses the
  channel without structural translation.
- The ios-bridge today only exposes
  `health`/`availability`/`capabilities`/`createSession`/`disposeSession`/`respond`
  (unary). **Streaming, countTokens, vision, and feedback must be exposed
  upstream** — the core already implements them; the work is surface-level.
- Separate repository (ADR-0009): the plugin consumes the SPM packages by git
  URL; development uses a local path override.

## 2. Decision

This repository (**`foundationmodels-dart`**) contains a **federated plugin**
of 3 pub.dev packages whose transport is an **in-process JSON-RPC over a
platform channel**: the MethodChannel carries `{method, params}` envelopes
identical to the daemon protocol (v2), and a multiplexed EventChannel carries
the stream events. The Flutter adapter never invents its own semantics — it
re-mirrors `docs/protocol.md`.

Consequences:

- (+) Near-automatic protocol parity: when upstream adds a method, the adapter
  exposes it by forwarding the envelope.
- (+) Contract tests reuse the v2 protocol fixtures as golden files.
- (+) The plugin's Swift is thin; logic changes happen upstream.
- (−) We depend on upstream ios-bridge extensions (streaming, vision, tokens)
  — controlled, since the author is the same.
- (−) Requires a **git mirror** of the Swift code for URL consumption (SPM
  does not accept a monorepo subdirectory as a remote dependency).

## 3. Goals / Non-goals

**Goals**

1. `health` / `availability` / `capabilities` / `respond` / `stream` /
   `sessions.*` / `context.countTokens` / `vision.ocr` / `vision.barcode` /
   `feedback.logAttachment` working on-device (iOS 27+, macOS 27+).
2. Typed Dart errors with 1:1 parity to `error.data.code` (table §7.3).
3. Deterministic mock provider in pure Dart — CI tests without a Mac
   (upstream's mock-first philosophy).
4. Streaming with functional cooperative cancellation.
5. Guided generation (JSON Schema → `DynamicGenerationSchema`) exposed via
   `extract()` and `responseFormat`.
6. On-device smoke suite mirroring `scripts/smoke/*`.

**Non-goals — real limits only** (see §17.3 for the full rationale; this
ADR's program is **maximum parity** with upstream):

- **Android / Windows / Linux backend** — Apple Foundation Models does not
  exist outside the Apple ecosystem (a platform limit, not a Flutter one).
  Contract parity via mock + interfaces; a future Gemini Nano provider would
  be another package under the same contracts.
- **PCC inference without entitlement** — blocked by Apple
  (`com.apple.developer.private-cloud-compute`), equally in TS. With the
  entitlement, Flutter inherits via the core (U9).
- **Literal Vercel AI SDK adapter** — there is nothing to port (TS
  ecosystem); parity is of capability, via Dart adapters (phase 8).

Everything else upstream is in the program: duplex tools (phase 4), RAG +
desktop daemon (phase 5), eval + traces (phase 6), **agent kit / HITL +
MLX/CoreAI** (phase 7), **OpenAI-compatible server + Dart adapters**
(phase 8). See §16 and §17.2.

---

## 4. Repository and package layout

```
foundationmodels-dart/                     (this repo, AGPL-3.0-only)
├── packages/
│   ├── foundationmodels/                  ← public Dart API + mock provider
│   │   ├── lib/src/{runtime,sessions,errors,mock,schema}/
│   │   └── test/                          (CI without a Mac)
│   ├── foundationmodels_platform_interface/
│   │   └── lib/                           (transport contract + stream events + errors)
│   └── foundationmodels_apple/            ← iOS+macOS implementation (plugin)
│       ├── ios/     (or shared darwin/)
│       │   ├── Package.swift              (plugin SPM → Swift mirror deps)
│       │   └── Classes/FoundationModelsPlugin.swift
│       └── macos/   (symlink/darwin sharing)
├── docs/
│   ├── parity.md                          (matrix mirroring upstream docs/parity.md)
│   └── protocol-mapping.md                (JSON-RPC method ↔ Dart call table)
├── scripts/smoke/                         (on-device smokes — §12)
└── .archagents/                           (governance mirrored from upstream)
```

> The three packages under `packages/` **already exist** (phase 0–1 scaffold):
> [`foundationmodels`](../../packages/foundationmodels),
> [`foundationmodels_platform_interface`](../../packages/foundationmodels_platform_interface),
> [`foundationmodels_apple`](../../packages/foundationmodels_apple). The
> [`docs/parity.md`](../parity.md) and
> [`docs/protocol-mapping.md`](../protocol-mapping.md) files are also in
> place.

Layout decisions:

- **Shared `darwin/`**: the same `FoundationModelsPlugin.swift` serves iOS and
  macOS — the Swift core is already dual-platform (the ios-bridge runs "iOS
  and host debugging on macOS"). Use Flutter's shared-directory convention.
  The current scaffold keeps `ios/` and `macos/` as separate SPM plugin
  directories; consolidating them is open question §18.3.
- **SPM for plugins** (stable Flutter support):
  `foundationmodels_apple/ios/Package.swift` declares the Swift dependencies —
  no podspec/CocoaPods for new code.
- **Examples**: separate repositories (ADR-0009), e.g.
  `fm-example-flutter-chat`, outside this repo.

## 5. Consuming the Swift core from a separate repo

SPM requires a `Package.swift` at the root of the remote repository —
`swift/FoundationModelsCore` inside the monorepo is not consumable by URL.
Decision:

1. **Distribution mirror** — new repo `cristianoaredes/foundationmodels-swift`
   with `Package.swift` at the root exporting **two products**:
   `FoundationModelsCore` and `FoundationModelsIOSBridge`. Synchronized from
   the monorepo by script (`git subtree split` or a CI-verified copy), tagged
   with its own semver (`swift-core/1.x.y`). Mirrors the model already used
   for the prebuilt daemon (`foundationmodels-daemon-darwin-arm64`): a
   distribution artifact derived from the monorepo.
2. **Pin in the plugin** — `foundationmodels_apple/ios/Package.swift`:
   ```swift
   // Package.swift (the manifest is Swift: it can read env)
   import Foundation
   let deps: [Package.Dependency]
   if let local = ProcessInfo.processInfo.environment["FOUNDATIONMODELS_SWIFT_PATH"] {
     deps = [.package(path: local)]                      // dev: monorepo checkout
   } else {
     deps = [.package(url: "https://github.com/cristianoaredes/foundationmodels-swift.git",
                      from: "1.0.0")]                    // distribution: pinned mirror
   }
   ```
   `FOUNDATIONMODELS_SWIFT_PATH` points to the local monorepo — analogous to
   the `FOUNDATIONMODELS_CORE_PATH` / `FOUNDATIONMODELS_IOS_BRIDGE_PATH`
   already used in the RN package's podspec.
3. **Upgrade policy**: the mirror only advances with a tag; this repo's
   `docs/parity.md` records the core version against which the matrix was
   measured.

## 6. Channel architecture

```
Dart (foundationmodels)                    Swift (foundationmodels_apple)
┌─────────────────────────┐               ┌────────────────────────────────┐
│ runtime.dart            │  MethodChannel│ FoundationModelsPlugin         │
│  respond/stream/...     │ ─────────────▶│  └─ route method+params        │
│ errors.dart (typed)     │  "foundationmodels/rpc"   └─ FoundationModelsBridge.shared
│ mock.dart               │ ◀─────────────│       (extended upstream)      │
└───────────┬─────────────┘  envelope     └────────────┬───────────────────┘
            │              {jsonrpc-ish}               │
            │ EventChannel "foundationmodels/streams"  │ FoundationModelsCore
            └──────────────────────────────────────────┴──► Apple FM framework
```

- **A single MethodChannel** `foundationmodels/rpc` with a single `invoke`
  operation, whose argument is the protocol envelope:
  `{"method": "foundationmodels.sessions.respond", "params": {...}, "id": "rpc_..."}`.
  Swift routes to the corresponding handler in the core. **Rationale:** keep
  the adapter structurally identical to the daemon's `JsonRpcHandler`; any
  future v2 method enters without a channel change.
- **A single EventChannel** `foundationmodels/streams` multiplexed by
  `requestId` (correlates with the envelope's `id`). Dart demultiplexes by
  `requestId` into the call's `StreamController`. Avoids creating/destroying
  channels per stream and mirrors the daemon's "events on the same
  connection" semantics.
- **Codec**: `StandardMessageCodec` (supports maps/lists/strings/numbers/
  binaries). Images via `base64` (same as v2) — path-based only makes sense
  with `allowedImageRoots`, which is kept.
- **Threading**: EventChannel sinks are called from a dedicated serial queue
  in Swift; MethodChannel responses come from the core's cooperative tasks
  (like the current `respondObjC`, which does not guarantee the main thread).
  The Flutter engine makes the hop to the platform thread — the plugin does
  **not** need to dispatch to main.
- **Timeouts**: Dart applies its own per-call timeout (mirroring
  `SOCKET_TIMEOUT` → `ModelTimeoutError`); the channel has no native timeout.

## 7. Wire protocol

### 7.1 Unary envelope (MethodChannel)

Request (argument of `invoke`):

```json
{
  "id": "rpc_9f2c",
  "method": "foundationmodels.sessions.respond",
  "params": {
    "sessionId": "ses_abc",
    "model": "apple.system",
    "input": [{"type": "text", "text": "Hello"}],
    "options": {"temperature": 0.2, "maximumResponseTokens": 128}
  }
}
```

Response: exactly the JSON-RPC `result` (no `jsonrpc`/`id` wrapper — the
channel already correlates). Failure: `FlutterError` with `code` = the
numeric JSON-RPC code as a string, `message`, and `details` = `error.data`
(includes the stable machine `code` — the real contract, per protocol.md:
"that string — not the numeric code or the message — is the contract clients
map to typed errors").

### 7.2 Stream events (EventChannel)

Same types as protocol v2, one `Map` per event:

`run_started` · `message_start` · `text_delta` · `structured_delta` ·
`tool_call_start` · `tool_call_delta` · `tool_call_result` · `message_end` ·
`done` · `error`

Every event carries `requestId`; when available, `sessionId` and `traceId`
(mirroring "Events must include sessionId, requestId, and traceId when
available"). Termination: `done` or `error` closes the corresponding Dart
`StreamController`; Swift removes the `requestId` registration.

### 7.3 Typed Dart errors

1:1 mapping of `error.data.code` (protocol.md table) to sealed Dart
exceptions:

| `error.data.code` | Dart exception |
|---|---|
| `APPLE_MODEL_UNAVAILABLE` (+`reasonCode`) | `AppleModelUnavailableException` |
| `UNSUPPORTED_PLATFORM` | `UnsupportedPlatformException` |
| `PCC_UNAVAILABLE` / `PCC_QUOTA_EXHAUSTED` | `PccUnavailableException` (with `pccFailureKind`, `retryable`) |
| `MULTIMODAL_INPUT_UNAVAILABLE` | `MultimodalInputUnavailableException` |
| `UNSUPPORTED_SCHEMA_TYPE` | `UnsupportedSchemaTypeException` (with `keyword`, `path`) |
| `TOOL_CALLBACKS_REQUIRE_STREAMING` | `ToolCallbacksRequireStreamingException` |
| `CONTEXT_OVERFLOW` | `ContextOverflowException` (with `contextSize`, `tokenCount` in SDK 27) |
| `GENERATION_CANCELLED` | `GenerationCancelledException` |
| `TOOL_EXECUTION_FAILED` | `ToolExecutionFailedException` (with `toolName`, `callbackCode`) |
| `GUARDRAIL_VIOLATION` / `MODEL_REFUSAL` | `GuardrailViolationException` / `ModelRefusalException` — never retryable |
| `RATE_LIMITED` / `MODEL_TIMEOUT` / `SESSION_BUSY` / `TRANSCRIPT_MUTATION_WHILE_RESPONDING` | `RateLimitedException` (with `resetDate`) / `ModelTimeoutException` / `SessionBusyException` / `TranscriptMutationException` — retryable |
| `STRUCTURED_OUTPUT_VALIDATION_FAILED` | `StructuredOutputValidationException` |
| `UNSUPPORTED_OPTION` / `UNSUPPORTED_OPERATION` / `UNSUPPORTED_TRANSCRIPT_CONTENT` / `UNSUPPORTED_GENERATION_GUIDE` / `UNSUPPORTED_LANGUAGE_OR_LOCALE` / `FEEDBACK_ATTACHMENT_UNAVAILABLE` / `SYSTEM_TOOL_UNAVAILABLE` / `VISION_*_UNAVAILABLE` | `Unsupported*Exception` family mirroring the TS types |
| `UNKNOWN_MODEL_ERROR` / absent | Generic `FoundationModelsException` with `details` |

Golden rule (inherited from upstream): **fail with a typed error, never
pretend it worked** — no silent cloud fallback, no silently dropped schema
keyword.

---

## 8. Public Dart API (`package:foundationmodels`)

Mirrors the `@orqo/foundationmodels` surface, in idiomatic Dart (no Flutter
dependency in the API package — testable in a plain VM). The scaffold already
lives in [`packages/foundationmodels`](../../packages/foundationmodels):

```dart
import 'package:foundationmodels/foundationmodels.dart';

final fm = await createFoundationModels(); // no provider → deterministic mock

// In a Flutter app with foundationmodels_apple registered:
final fm = await createFoundationModels(
  providers: [AppleFoundationModelsProvider()],
);

final cls = await fm.classify(input: 'I love this product!', labels: ['positive', 'negative']);

final city = await fm.extract(
  input: 'Paris is in France.',
  schema: FmSchema.object({'city': FmSchema.string(), 'country': FmSchema.string()}),
);

final session = await fm.createSession(instructions: 'Answer concisely.');
await for (final event in session.stream(input: 'One sentence on on-device AI.')) {
  if (event is TextDelta) stdout.write(event.delta);
}
await session.dispose();
```

Design points:

- **`FmSchema` instead of Zod**: Dart has no mature equivalent; define a
  typed builder that generates **exactly the JSON Schema subset the Swift
  core accepts** (object with `required`, array with `minItems`/`maxItems`,
  string with `pattern`/`const`/`enum`, number/integer with
  `minimum`/`maximum`, boolean, `anyOf`, `$ref` to `#/$defs/*`, nullable
  `type: ["T","null"]`). Out-of-subset keywords fail **locally** with
  `UnsupportedSchemaTypeException` before crossing the channel — the same
  fail-fast behavior as upstream.
- **`availability()`** returns a stable `reasonCode` (`device_not_eligible`,
  `apple_intelligence_not_enabled`, `model_not_ready`...) so the app can
  feature-detect and degrade gracefully.
- **Lazy sessions**, mirroring upstream semantics (protocol.md "Instruction
  Precedence"): `createSession()` mints a local `ses_*`; the native session
  is born on the first respond/stream; `instructions` of subsequent requests
  on an existing session are ignored (first request wins); changing them
  requires `transition()` (preserves transcript), `create()` with the same
  id, or `dispose()`+recreate (blank transcript). Document this in the Dart
  API with the same prominence — it is the #1 trap for upstream consumers.
- **`contextPolicy: guard | compact`** — guard calls `context.countTokens`
  before generating and raises a local `ContextOverflowException` with the
  full breakdown (parity with the TS runtime).
- **`usage`**: expose `estimated` prominently; `estimated:false` only when
  natively measured (SDK 27); consumers must not treat an estimate as a
  measurement.
- **Cancellation**: Dart `CancelToken` (analogous to `AbortSignal`) — see
  §10.

## 9. Required upstream extensions (ios-bridge)

The adapter depends on exposing in `FoundationModelsBridge` what today only
exists in the daemon. Upstream tickets (project SPC/TCK style); the
executable specification of each ticket lives in
[`upstream-ios-bridge-extensions.md`](upstream-ios-bridge-extensions.md):

| # | Extension | Existing base in the core | Effort |
|---|---|---|---|
| U1 | `respondStream(params:onEvent:)` — per-delta callback | `StreamingDelta.swift`; daemon `sessions.stream` handler | Medium |
| U2 | `countTokens(params:)` | `SystemLanguageModel.tokenCount(for:)` (already in the daemon) | Low |
| U3 | `visionOcr` / `visionBarcode` (base64, EXIF-aware) | `VisionHandler.swift` | Low |
| U4 | `logFeedbackAttachment(params:)` | `feedback.logAttachment` handler | Low |
| U5 | `createSession/transition/prewarm` with `history` | `sessions.create/transition/prewarm` + `SessionRegistry` | Low |
| U6 | In-process cancellation by `generationId` | daemon cooperative cancel (`streamResponse` Task) | Medium |
| U7 | In-process duplex tool calling (phase 4) | daemon socket-scoped tool bridge → re-scope to a Swift callback | High |
| U8 | Expose MLX/CoreAI backends (`apple.mlx:*`, `apple.coreai:*`) on the ios-bridge | `MLXInferenceBackend.swift`, `CoreAIInferenceBackend.swift`, `CoreAIModelRegistry.swift` — already run in the core; only in-process surface is missing | Medium |
| U9 | In-process PCC in an entitled build | availability/quota already exist; inference requires `com.apple.developer.private-cloud-compute` | High (gated by Apple) |

**Architectural principle (non-negotiable):** none of this logic is
reimplemented in the Flutter plugin — the ios-bridge calls the same
`FoundationModelsCore` methods that the `JsonRpcHandler` uses. The plugin
only translates channel ↔ dictionary.

## 10. Cancellation

Semantics inherited from protocol.md, adapted to the in-process transport:

- **Streaming**: `CancelToken.cancel()` in Dart → an `invoke` method call
  with `{"method": "foundationmodels.generation.cancel", "params": {"generationId": "<requestId>"}}`
  → Swift cancels the native streaming `Task` (U6) → the stream ends with an
  `error`/`GENERATION_CANCELLED` event and the `StreamController` closes with
  `GenerationCancelledException`. Repeated cancellations are idempotent.
- **Declared scope** (copied from upstream, verbatim in spirit): only
  streaming is truly interruptible. Cancelling a unary `respond` stops Dart
  from waiting, but does not stop the native generation — documented in the
  docstring, as upstream does ("Do not read 'cancellation is reachable from
  the public API' as 'every operation is interruptible'").
- **Abandonment**: if the app cancels the Stream subscription without a
  `CancelToken`, Dart sends the cancel implicitly — analogous to the daemon's
  "client EOF is an implicit cancel".

## 11. Duplex tool calling (phase 4 — recorded design)

The most delicate case of the port. Daemon model: `tool_call_request` emitted
mid-stream; the client executes and returns `tools.result` **on the same
connection**; callback failure aborts the generation with
`TOOL_EXECUTION_FAILED` + `callbackCode`.

Mapping to channels:

1. A `tool_call_request` event arrives on the EventChannel with `requestId` +
   `toolCallId`.
2. The Dart runtime executes the registered callback and sends `invoke` with
   `{"method": "foundationmodels.tools.result", "params": {"toolCallId": ..., "result" | "error": ...}}`.
3. Swift blocks the native generation until the result (a completer per
   `toolCallId`) — the same "block until tools.result arrives" contract.
4. Inherited policies: callback tools are **stream-only** (`respond` rejects
   with `ToolCallbacksRequireStreamingException` — enforced locally in Dart
   before the channel, as the TS provider does); request-scoped, never
   persisted in a session; callback error (`TOOL_CALLBACK_ERROR`/
   `TOOL_CALLBACK_NOT_FOUND`) propagates as `ToolExecutionFailedException`
   with `toolName`/`callbackCode`.
5. **Native tools** (`{"native": "ocr"}`, `{"native": "barcode"}`) execute
   inside the process without a callback — also available in `respond`,
   requiring an image with a `label` (ImageReference/attachmentLabel). No
   design change.

A static tool (`staticOutput`) works from phase 3 without any of this.

## 12. Security and privacy (invariant parity)

- **Offline by default**: the mock never does network; the Apple provider
  stays on-device; **no silent cloud fallback** — a central upstream
  invariant, copied as a contract test.
- **`instructions` = trusted channel**: docstring and internal lint — never
  interpolate user input, tool results, or web content into `instructions`
  (rule TCK-0209/FND-0142). The Dart runtime never concatenates untrusted
  text into instructions on any path.
- **Image allowlist**: `allowedImageRoots` fail-closed (without an allowlist,
  paths are rejected), realpath with symlink-awareness in the core — Dart
  only forwards; inline images via `base64` with `mimeType`, and `label` as
  metadata outside the allowlist (TCK-0227).
- **PII redaction + audit**: port of `foundationmodels-policy` as an optional
  Dart package (phase 3), `"off"|"log-only"|"auto"` modes with audit entries.
- **Secrets**: never log tokens; serialized errors never carry the model's
  `rawContent` (parity with `STRUCTURED_OUTPUT_VALIDATION_FAILED`).

## 13. Platform requirements and availability gating

| | |
|---|---|
| iOS | 27+, Apple Intelligence enabled, eligible device (Apple Silicon-class NPU) |
| macOS | 27+, Apple Silicon |
| Toolchain | Xcode 27 / SDK 27; stable Flutter with SPM for plugins |
| Feature-detect | `availability()` + `capabilities()` before using streaming, guided gen, multimodal, native tools, vision, feedback — the app degrades by `reasonCode` |

On-device tests require Apple hardware (simulator with partial coverage — the
same caveat as upstream, which measures smokes on real macOS 27).

## 14. Testing strategy

Three layers, mirroring the upstream pyramid:

1. **Unit + contract (CI, no Mac)** — deterministic mock provider; golden
   fixtures of protocol v2 (requests/responses/events/errors extracted from
   `docs/protocol.md`); error→exception mapping tests for **every** row of
   the §7.3 table; `FmSchema` tests (accepts the subset, rejects
   `oneOf`/`format`/`minLength`... with the keyword named).
2. **Channel contract (CI with a mocked host)** — `foundationmodels_apple`
   tested against a fake `FoundationModelsPlugin` that replays recorded
   envelopes; validates `requestId` demultiplexing, cancellation, event
   ordering (`text_delta`→`done`; `structured_delta`→`result`→`done`).
3. **On-device smokes (real Apple Silicon)** — mirror of `scripts/smoke/*`:
   `availability`, `textgen` (respond, session recall, overflow), `streaming`
   (deltas + cancel), `sessions`/`instructions`/`sampling`, `guidedgen`,
   `multimodal`, `vision`, `toolcalling` (phase 4). Release criterion: all
   green on the target device, results recorded in `docs/parity.md` with date
   and core build.

## 15. Versioning and parity policy

- `foundationmodels` (Dart API): its own semver from `0.1.0`; `1.0.0` when
  streaming + guided gen + sessions are measured on-device.
- `foundationmodels_apple`: carries in its `pubspec.yaml`/README the version
  of the `foundationmodels-swift` mirror it was validated against (e.g.
  `core: swift-core/1.2.0`).
- Local `docs/parity.md`: `supported/partial/blocked/unsupported` matrix
  **mirrored** from upstream, with evidence (smoke + date + device) for each
  cell — the same discipline of "never report a capability as supported
  unless it uses the native Apple API or documents a precise fallback".
- Compat: the v1 envelope remains accepted; v2 features go through
  feature-detect via `capabilities()`.

## 16. Phased plan and acceptance criteria

| Phase | Content | Acceptance |
|---|---|---|
| **0 — Spike** (2–3 days) | Repo created; `foundationmodels_apple` with `invoke` routing `health/availability/respond`; Swift mirror published or local path | `respond("Hello")` returns real model text on an iOS 27+ device; envelope identical to the daemon |
| **1 — Dart core** (1–2 wk) | `foundationmodels`: contracts, typed errors, mock, `FmSchema`, `classify/extract/rank/summarize/respond/createSession` | CI suite green without a Mac; protocol golden fixtures passing |
| **2 — Streaming** (1 wk) | U1+U6 upstream; multiplexed EventChannel; `CancelToken` | `streaming` smoke green: incremental deltas, functional cancel, typed `GENERATION_CANCELLED` |
| **3 — Full surface** (2–4 wk) | U2–U5; guided gen; multimodal; vision; feedback; `contextPolicy: guard`; policy/redaction | `guidedgen`, `multimodal`, `vision`, `sessions`, `instructions` smokes green; parity.md filled with evidence |
| **4 — Tools** (2–4 wk, optional) | U7; duplex tool calling; native tools; static tools; `SchemaMode.tool` (sanitization) | `toolcalling` smoke green; `TOOL_CALLBACKS_REQUIRE_STREAMING` enforced locally |
| **5 — RAG + desktop** (2–4 wk, optional) | Semantic index (local RAG); daemon client for Flutter desktop macOS | Equivalent `semantic-rag` smoke green; `respond` via Unix socket on desktop |
| **6 — Eval + traces** (2–3 wk, optional) | Port of the eval harness; traces contract | Eval suite running against mock + device; traces inspectable end-to-end |
| **7 — Agent kit + MLX/CoreAI** (3–5 wk, optional) | Port of `foundationmodels-agent` (tool loops, consume-once HITL, intent router, AG-UI events, optional MCP); U8 exposes MLX/CoreAI | Tool loop with HITL end-to-end on device; `respond` with a registered `apple.mlx:*` model |
| **8 — Ecosystem** (1–2 wk, optional) | OpenAI-compatible server in Dart (`shelf`); adapters for Dart LLM clients | `curl /v1/chat/completions` serves the on-device model; adapter published |

**Maximum parity (phases 0–8 complete):** ~100% of the upstream surface —
runtime + tools + RAG + eval + agent + server — except the two real limits of
§17.3 (PCC without entitlement; Android backend).

> Phase-specific specs (written as each phase starts):
> [`phase-2-streaming.md`](phase-2-streaming.md),
> [`phase-3-full-surface.md`](phase-3-full-surface.md),
> [`phase-4-tools.md`](phase-4-tools.md),
> [`phase-5-rag-and-desktop.md`](phase-5-rag-and-desktop.md),
> [`phase-6-eval-traces.md`](phase-6-eval-traces.md),
> [`phase-7-agent-kit-mlx.md`](phase-7-agent-kit-mlx.md),
> [`phase-8-ecosystem.md`](phase-8-ecosystem.md).

## 17. Coverage matrix vs. upstream

Item-by-item audit against the monorepo. Nothing may remain outside this
table without a classification — a governance invariant of this repo.

### 17.1 Covered in this ADR

| Upstream surface | Section |
|---|---|
| Primitives `classify` / `extract` / `rank` / `summarize` / `respond` / `stream` / `policyCheck` (core) | §8 |
| Sessions (lazy, 30 min TTL/LRU 256, `transition`, `prewarm`, `history`) | §8, U5 |
| Streaming v2 + cooperative cancellation | §7.2, §10 |
| Guided generation (output schemas) with the JSON Schema subset | §8 |
| Typed errors (`error.data.code` → Dart exceptions) | §7.3 |
| `context.countTokens` / `contextPolicy: guard\|compact` / usage (`estimated`) | §8, U2 |
| Multimodal (path/base64, allowlist, EXIF, `label`) | §12 |
| Vision OCR/barcode (methods + native tools) | U3, §11 |
| Feedback attachment | U4 |
| Deterministic mock provider | §8 |
| Policy/redaction/audit (`off`/`log-only`/`auto`) | §12, phase 3 |
| Availability/capabilities + reasonCodes + feature-detect | §13 |

### 17.2 Deferred scope (enters this repo's roadmap, with a phase)

| Item | Scope note | Target phase |
|---|---|---|
| **Duplex tool calling + native tools** | design in §11 | 4 |
| **Tool schema sanitization** | **Nuance inherited from core ≥ 1.0.1:** non-honorable keywords in *tools* (`maxLength`, `pattern`, `oneOf`...) are **stripped at the provider edge**; *output schemas* remain fail-fast. `FmSchema` implements both modes: `SchemaMode.tool` (sanitizes) vs. `SchemaMode.output` (rejects) | 4 (with tools); `output` from phase 1 |
| **Semantic index (local RAG)** | Port of the semantic index (pluggable embeddings, O(1) id map) — pure TS logic, portable; depends on an on-device embeddings strategy (provider TBD: native via core or Dart) | 5 |
| **Daemon client (Flutter desktop macOS)** | Pure-Dart client of the prebuilt daemon over a Unix socket (`dart:io`, `InternetAddressType.unix`), identical v1/v2 protocol — a second `IntelligenceProvider` under the same contracts | 5 |
| **Eval harness** | Port of `@orqo/foundationmodels-eval` (harness + traces) — depends on traces (below) | 6 |
| **Traces** | `traceId` propagation/inspection beyond stream events (the core's traces contract) | 6 |
| **Config knobs** (`useCase`, `guardrails`, `maxTotalImageBytes`) | Runtime config surface — exposed on the Dart `createFoundationModels` | 3 |
| **Agent kit** (`foundationmodels-agent`) | Pure TS logic over the primitives — tool loops, HITL approve/edit/reject with consume-once interrupts, intent router (`classifyRouteIntent`), AG-UI-shaped events, optional MCP tools (JSON-RPC over stdio/HTTP — portable). **Fully portable**; sequenced after duplex tools | 7 |
| **MLX / CoreAI** (`apple.mlx:*`, `apple.coreai:*`) | **Already runs in the Swift core** — depends only on U8 (ios-bridge exposure). The Flutter envelope already accepts the model ids; availability reports the real state | 7 (after U8) |
| **OpenAI-compatible server (Dart equivalent)** | The original is Node; the `shelf` equivalent is new but simple code — serves the Mac/iOS on-device model over HTTP (`/v1/chat/completions`, `/v1/models`, `/health`, bearer, CORS, TLS) | 8 |
| **Dart ecosystem adapters** (LangChain.dart etc.) | **Capability** parity with the Vercel AI SDK adapter — new code, idiomatic Dart form | 8 |
| **PCC inference** | Inherits automatically from the core **if/when** an entitled build exists (U9) — availability/quota already exposed since phase 3 | gated (U9) |
| **Android provider (Gemini Nano / ML Kit GenAI)** | **Contract** parity, never backend parity: same Dart interfaces, separate provider. The mock already runs on Android from phase 1 | future ADR |

### 17.3 Real limits (what is NOT possible — and why)

Only two limits exist, both external to Flutter:

| Limit | Nature |
|---|---|
| **PCC inference without entitlement** | An **Apple** restriction (`com.apple.developer.private-cloud-compute`) — affects TS equally. Not a Dart limitation: with the entitlement, Flutter inherits via the core (U9) |
| **Android backend** | The Apple Foundation Models framework **does not exist** outside the Apple ecosystem. Maximum possible: contract parity + an alternative provider (Gemini Nano), which is another backend, not a port |

**Everything else upstream is reachable in Dart/Flutter** — either because it
is portable pure logic (agent, eval, RAG, policy, server-equivalent), or
because it already lives in the Swift core and only needs ios-bridge surface
(MLX/CoreAI, duplex tools). The maximum-parity program is therefore **~100%
of the runtime + agent + eval + RAG + server surface**, limited only where
Apple itself limits.

> **Note — dynamic profiles / Spotlight tool:** upstream marks `partial`;
> `profile` travels in the envelope as metadata (no native instructions) —
> automatic parity, no additional work. Recorded here only so it does not
> leave the matrix.

## 18. Open questions

1. **Swift mirror**: automated `git subtree split` vs. a hand-maintained repo
   with a sync script — decide in phase 0 (impacts the monorepo release
   flow).
2. **pub.dev name**: is `foundationmodels` available? Fallback:
   `orqo_foundationmodels` (aligns with the `@orqo` npm org).
3. **Shared `darwin/` vs. separate `ios/`+`macos/`**: validate in phase 0
   with the current Flutter toolchain whether the shared directory covers
   both without duplicating `Package.swift`. The current scaffold uses
   separate `ios/` and `macos/` plugin directories.
4. **Transcript reading**: upstream does not expose `.reasoning` entries on
   the wire; does Flutter follow suit or record it as a gap in the local
   parity matrix?
5. **PCC**: entitlement strategy — the Flutter app/plugin would need to sign
   with its own entitlement for in-process PCC (U9); availability/quota work
   without it.
6. **Semantic index embeddings** (phase 5): native provider via the core (if
   Apple exposes on-device embeddings) vs. a Dart implementation — a design
   decision that affects RAG result parity.

## 19. References

- `docs/protocol.md` (upstream) — transport contract, v1/v2 methods, events,
  errors, cancellation, auth.
- `docs/parity.md` (upstream) — capability matrix and evidence discipline.
  Local mirror: [`../parity.md`](../parity.md).
- `swift/ios-bridge/Sources/FoundationModelsIOSBridge/Bridge.swift` —
  current in-process surface.
- `packages/foundationmodels-react-native` (upstream) — reference host (thin
  adapter).
- [`upstream-ios-bridge-extensions.md`](upstream-ios-bridge-extensions.md) —
  executable specification of tickets U1–U9 (§9).
- ADR-0002 (Swift core as single source), ADR-0009 (separate repos),
  ADR-0012 (local-first verification) — monorepo `.archagents/09-decisions/`.
