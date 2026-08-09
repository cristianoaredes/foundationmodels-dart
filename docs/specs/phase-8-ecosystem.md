# Phase 8 — Ecosystem: OpenAI-compatible server, Dart adapters, pub.dev

Implementation spec for ADR-0001 §16 phase 8 ("Ecossistema"): (a) an
OpenAI-compatible HTTP server in pure Dart (`shelf`) serving the on-device
model, (b) Dart ecosystem adapters with capability parity to the upstream
Vercel AI SDK adapter, and (c) pub.dev publication readiness.

## Goal

(a) Any OpenAI client can hit the on-device model over HTTP:
`POST /v1/chat/completions` (unary + SSE streaming), `GET /v1/models`,
`GET /health`, with `--port`/`--host`/`--bearer-token`/`--cors`/`--https`
flags. Capability parity with the upstream Node server — same endpoint
shapes — implemented idiomatically in Dart.

(b) Dart ecosystem consumers get first-class adapters — starting with
LangChain.dart (`ChatFoundationModels`) — covering the same *capabilities*
as the upstream AI SDK adapter (text, streaming, guided generation, tool
calling), in idiomatic Dart form (ADR-0001 §3: parity of capability, not a
literal port).

(c) All publishable packages pass `dart pub publish --dry-run` with hosted
dependencies, real versions, and LICENSE/NOTICE intact.

## Depends on

- Phases 1–4 (runtime, streaming, tools) for full server capability; the
  server degrades honestly per `capabilities()` when a feature is missing.
- Phase 5 optional (the server may front either provider: in-process plugin
  or daemon transport).
- `shelf`, `shelf_router` (server); `langchain_core` (adapter).

## Scope

### In

- New package `packages/foundationmodels_server/` (pure Dart, `dart:io` +
  `shelf`): CLI binary + embeddable handler.
- OpenAI-compatible mapping: chat messages → `FmRequest` input/instructions;
  responses → OpenAI `chat.completion` / chunk shapes; SSE streaming with
  `data: [DONE]`; `usage` fields populated with `estimated` preserved.
- Flags: `--port` (default 11435), `--host` (default 127.0.0.1),
  `--bearer-token`, `--cors` (off by default; on → permissive dev CORS),
  `--https` (cert/key paths).
- Error mapping: typed `FoundationModelsException` → OpenAI error envelope
  with correct HTTP status (e.g. `RATE_LIMITED` → 429,
  `CONTEXT_OVERFLOW` → 400 with `code` in the body; guardrails → 400,
  never retried by the server itself).
- `packages/foundationmodels_langchain/`: `ChatFoundationModels` adapter.
- pub.dev readiness across publishable packages.
- Smoke: `curl /v1/chat/completions` against the on-device model on macOS.

### Out

- OpenAI endpoints beyond the three above (no `/v1/embeddings`,
  `/v1/images`, fine-tuning, etc. — the core does not provide them;
  absent endpoints return 404, never stubs).
- Auth beyond a single bearer token (no users/keys management).
- Adapters for every Dart LLM framework — LangChain.dart is the reference;
  additional adapters follow the same pattern as follow-ups.

## API deltas

### (a) `packages/foundationmodels_server/`

```dart
/// Embeddable server. The CLI binary (`bin/foundationmodels_server.dart`)
/// is a thin arg-parser over this class.
final class FmOpenAiServer {
  FmOpenAiServer({
    required FoundationModels runtime,
    String host = '127.0.0.1',
    int port = 11435,
    String? bearerToken,          // null = no auth (loopback default)
    bool cors = false,            // dev CORS when true
    SecurityContext? tls,         // from --https cert/key
  });

  Future<void> start();
  Future<void> stop();

  /// The shelf handler, exposed for embedding/testing without a socket.
  Handler get handler;
}
```

CLI:

```
dart run foundationmodels_server -- \
  --port 11435 --host 127.0.0.1 \
  [--bearer-token TOKEN] [--cors] [--https cert.pem key.pem] \
  [--daemon-socket PATH | --in-process]
```

Wire mapping (must be fixture-tested against the upstream server's recorded
responses):

- Request: `messages` → system messages become `instructions` **only when
  caller-supplied and static** — the server treats remote client content as
  untrusted: system prompts travel in the request's system slot per protocol
  (trusted-channel rules apply to whoever deploys the server; documented
  loudly); user/assistant messages concatenate into `input` (with the
  session-less stateless mapping; multi-turn uses the transcript replay the
  upstream server does). `response_format: {"type": "json_object" | json schema}`
  → `FmSchema.raw` (fail-fast `SchemaMode.output`; schema errors → 400).
  `stream: true` → SSE. `temperature`/`max_tokens` → `GenerationOptions`.
- Response: `chat.completion` with `choices[0].message.content`,
  `usage: {prompt_tokens, completion_tokens, total_tokens}` populated from
  `Usage` (with an `"estimated": true` extension field preserved);
  streaming emits `chat.completion.chunk` deltas and terminates with
  `data: [DONE]`.
- Errors: OpenAI error envelope `{"error": {"message", "type", "code"}}`
  where `code` is the stable machine string (`error.data.code`); statuses:
  400 (context overflow, schema, guardrails, refusals), 401 (bad bearer),
  429 (`RATE_LIMITED`, honoring `resetDate` → `Retry-After`), 503
  (`APPLE_MODEL_UNAVAILABLE` with `reasonCode` in the body).

### (b) `packages/foundationmodels_langchain/`

```dart
/// LangChain.dart chat model backed by FoundationModels — capability
/// parity with the upstream AI SDK adapter.
final class ChatFoundationModels extends BaseChatModel {
  ChatFoundationModels({required FoundationModels runtime,
      String model = 'apple.system', GenerationOptions? defaultOptions});

  // Implements: invoke (unary), stream (token deltas), tool binding
  // (LangChain tool specs → FmTool with SchemaMode.tool sanitization),
  // structured output (withStructuredOutput → FmSchema + extract path).
}
```

### (c) pub.dev readiness — no API; mechanical changes

- Remove `publish_to: none` from publishable packages
  (`foundationmodels`, `foundationmodels_platform_interface`,
  `foundationmodels_apple`, `foundationmodels_policy`,
  `foundationmodels_rag`, `foundationmodels_daemon`,
  `foundationmodels_eval`, `foundationmodels_agent`,
  `foundationmodels_server`, `foundationmodels_langchain` — subject to
  name availability; fallback naming `orqo_*` per ADR-0001 §18.2).
- Replace `path:` inter-dependencies with hosted version constraints
  (`^x.y.z`) in publish order (platform_interface → foundationmodels →
  plugins/add-ons); keep the workspace `resolution: workspace` for local
  dev.
- Keep `LICENSE` (AGPL-3.0-only) and `NOTICE` at repo root; copy `LICENSE`
  into each package directory (pub requires per-package license files).
- Per-package: README, `example/` (or `example/lib/main.dart`), `topics:`
  in pubspec, `repository:`/`issue_tracker:` URLs, changelog entries.

## Work items

1. **Server skeleton.** `FmOpenAiServer` + CLI arg parsing; `GET /health`
   (build/version/availability passthrough) and `GET /v1/models` (from
   `capabilities()` — at minimum `apple.system` plus any registered
   `apple.mlx:*`/`apple.coreai:*` ids post-U8).
2. **Chat completions unary.** Request/response mapping per the wire
   contract above; fixture-tested against recorded upstream server
   responses (same request → same-shaped response).
3. **SSE streaming.** Map `FmStreamEvent`s to `chat.completion.chunk`s
   (`TextDelta` → content delta; `StreamDone` → final chunk + `data: [DONE]`;
   `StreamError` → error chunk then close); client disconnect maps to
   `CancelToken` cancel (implicit-cancel parity with the daemon's EOF
   semantics).
4. **Auth/CORS/TLS flags.** Bearer middleware (constant-time compare; token
   never logged, ADR-0001 §12), opt-in CORS headers, `SecurityContext`
   wiring for `--https`. Defaults are loopback + no auth — documented as
   dev posture; non-loopback bind without a token prints a loud warning.
5. **Error mapping.** Typed exceptions → statuses/codes per the table
   above; `Usage.estimated` never dropped; errors never carry raw model
   content (inherited invariant — pin with tests).
6. **LangChain adapter.** `ChatFoundationModels` with invoke/stream/tool
   binding/structured output; conformance to `langchain_core` chat-model
   contracts; tests against `MockProvider`.
7. **Provider selection in the server.** `--daemon-socket` uses
   `DaemonSocketTransport` (phase 5); `--in-process` is for Flutter-embedded
   deployments (documented; the pure-Dart server binary itself targets
   macOS desktop with the daemon transport as the default path).
8. **Publication prep.** Execute the mechanical list in (c); run
   `dart pub publish --dry-run` per package in dependency order and fix all
   warnings; verify `dart analyze --fatal-infos` and `dart test` per package.
9. **Smoke.** On an Apple Silicon Mac: start the server (daemon transport),
   `curl -s localhost:11435/v1/chat/completions` (unary and `stream: true`),
   `curl /v1/models`, `curl /health`; verify a real on-device answer and
   SSE chunk sequence. Record evidence in `docs/parity.md` (new rows:
   `OpenAI-compatible server (Dart)`, `Dart ecosystem adapters`).
10. **Capability-parity checklist for the adapter.** Write the explicit
    mapping table (AI SDK capability → LangChain.dart equivalent → status)
    into the adapter README: text, streaming, structured output, tool
    calling, cancellation — each `supported`/`partial` with a note; this is
    the ADR-0001 §3 "parity of capability" evidence.

## Test plan

### Unit (CI, no Mac)

- Request/response mapping fixtures (golden files from the upstream server).
- SSE sequence: chunks in order, terminal `[DONE]`, error chunk shape.
- Error mapping table: every typed exception → expected status + `code`.
- Bearer auth: missing/wrong token → 401; token absent from logs.
- LangChain adapter: invoke/stream/tools/structured against the mock.

### Contract (CI)

- `shelf` handler tested in-process (no socket): full request lifecycle for
  unary + SSE, disconnect → cancel propagation verified with a scripted
  provider.
- Adapter conformance tests from `langchain_core` test utilities.

### On-device smoke (Apple Silicon)

- Work item 9; plus a LangChain.dart example app round-trip against the
  real provider.

## Acceptance criteria

- [ ] `curl /v1/chat/completions` returns a real on-device answer, unary and
      SSE-streamed, terminating with `data: [DONE]`.
- [ ] `/v1/models` and `/health` reflect the real `capabilities()` state.
- [ ] `--port/--host/--bearer-token/--cors/--https` all work; non-loopback
      without token warns loudly; tokens never logged.
- [ ] Typed errors map to correct HTTP statuses with stable `code`s and
      `Retry-After` on `RATE_LIMITED`.
- [ ] `usage` fields populated with `estimated` preserved end-to-end.
- [ ] Client disconnect cancels the native generation (no orphaned work).
- [ ] `ChatFoundationModels` passes LangChain.dart conformance tests;
      capability-parity table written with honest statuses.
- [ ] Every publishable package passes `dart pub publish --dry-run` with
      zero warnings, hosted deps, per-package LICENSE, and working examples.
- [ ] `docs/parity.md` updated; CI green without a Mac.

## Estimate

1–2 weeks (matches ADR-0001 §16). Server mapping + fixtures are most of it;
the adapter and publication mechanics are parallelizable and low-risk.
