# Phase 7 — Agent kit (tool loops, HITL, intent router) + MLX/CoreAI

Implementation spec for ADR-0001 §16 phase 7: (a) the port of
`foundationmodels-agent` — tool loops with AG-UI-shaped events, HITL
interrupts, intent router, optional MCP tools — and (b) MLX/CoreAI model
support once upstream ticket U8 exposes those backends on the ios-bridge.

## Goal

(a) Apps can run an autonomous-but-supervised tool loop on top of the
phase-4 duplex tool calling: the agent streams AG-UI-shaped events, pauses
on **human-in-the-loop interrupts** (approve/edit/reject) that are
consume-once and replay-safe, resumes by interrupt id within a TTL, routes
intents via `classifyRouteIntent`, and maps `AbortSignal`-style control onto
the existing `CancelToken`.

(b) `apple.mlx:*` and `apple.coreai:*` model ids work through the existing
`model` parameter with honest capability reporting: the direct path rejects
unsupported options (`tools`, context options) locally with
`UnsupportedOptionException`, and `availability()`/`capabilities()` report
the real backend state.

## Depends on

- Phase 4 (duplex tools, `FmTool`, `ToolCallRequest`, typed tool errors).
- Phase 2 (streaming + `CancelToken`), phase 6 optional (traces plug into
  the agent loop for observability).
- Upstream ticket **U8** for (b): MLX/CoreAI exposure on
  `FoundationModelsBridge` (`MLXInferenceBackend.swift`,
  `CoreAIInferenceBackend.swift`, `CoreAIModelRegistry.swift` already run in
  the core; only the in-process surface is missing). The Flutter envelope
  already carries arbitrary model ids — no wire change needed.
- Upstream `foundationmodels-agent` sources for HITL/interrupt semantics,
  prototype-pollution guards on edited args, `classifyRouteIntent`, AG-UI
  event shapes, and the MCP client (JSON-RPC over stdio/HTTP).

## Scope

### In (a — agent kit, package `packages/foundationmodels_agent/`)

- `FmAgent` tool loop over `FoundationModels` streaming with `FmTool`s.
- AG-UI-shaped event stream (Dart sealed classes mirroring AG-UI event
  taxonomy: run lifecycle, text message, tool call, custom).
- HITL: `approve` / `edit` / `reject`; interrupts are **consume-once**
  (replay blocked), resume by interrupt id with TTL; `editedArgs` validated
  against the tool's `inputSchema` **and** the upstream prototype-pollution
  guards (reject `__proto__`, `constructor`, `prototype` keys at any depth).
- Intent router: `classifyRouteIntent` port (guided-generation classifier
  mapping input to a route id, using the runtime's `classify`).
- Control: `AbortSignal` semantics mapped to `CancelToken` (one public
  cancellation type — the existing `CancelToken`; document the mapping).
- Optional MCP tools: MCP client (JSON-RPC over stdio and HTTP) adapting
  MCP tool definitions into `FmTool.callback` (schemas pass through
  `SchemaMode.tool` sanitization).
- On-device HITL end-to-end run.

### In (b — MLX/CoreAI)

- Model-id routing: `apple.mlx:*` / `apple.coreai:*` flow through
  `FmRequest.model` unchanged.
- Local direct-path restrictions: when `model` is an MLX/CoreAI id, requests
  carrying `tools` or context options the backend rejects fail **locally**
  with `UnsupportedOptionException(options: [...])` before the channel.
- Availability reporting: `capabilities()` surfaces the backend registry
  state (model ids, loaded/downloadable); parity row per backend.

### Out

- Agent persistence/checkpoint stores beyond in-memory interrupt registries
  (callers may wrap; not part of the port).
- Multi-agent orchestration.
- PCC inference (U9, gated).
- Fine-tuning/adapter management for MLX models.

## API deltas

### (a) `packages/foundationmodels_agent/`

```dart
/// AG-UI-shaped events (mirroring the AG-UI taxonomy; wire-compatible
/// `type` strings so Dart events serialize to AG-UI JSON directly).
sealed class FmAgentEvent {
  String get type; // "RUN_STARTED", "TEXT_MESSAGE_CONTENT",
                   // "TOOL_CALL_START", "TOOL_CALL_END", "RUN_FINISHED",
                   // "RUN_ERROR", "INTERRUPT", ...
}

/// A human-in-the-loop pause. Consume-once: [resume] with this id exactly
/// once within [expiresAt]; replays are rejected (see FmInterruptRegistry).
final class FmInterrupt {
  final String id;               // "int_..."
  final FmInterruptKind kind;    // approve | edit | reject-pending
  final String toolName;
  final Map<String, Object?> proposedArgs;
  final DateTime expiresAt;      // TTL, default 10 min (upstream parity)
}

enum FmInterruptDecision { approve, edit, reject }

final class FmAgent {
  FmAgent({
    required FoundationModels runtime,
    required List<FmTool> tools,
    String? instructions,        // trusted channel — same rules as runtime
    FmInterruptPolicy interruptPolicy = const FmInterruptPolicy.requireForAllTools(),
    FmInterruptRegistry? interrupts, // in-memory default
    Duration interruptTtl = const Duration(minutes: 10),
  });

  /// Runs the loop: model ↔ tools until completion, emitting AG-UI-shaped
  /// events. Yields FmInterrupt events when HITL gates fire; the run
  /// suspends until [resume] consumes the interrupt.
  Stream<FmAgentEvent> run({required String input, CancelToken? cancelToken});

  /// Resumes a suspended run by interrupt [id].
  /// - approve: executes [proposedArgs] as-is.
  /// - edit: executes [editedArgs] after validation — schema-validated
  ///   against the tool inputSchema AND prototype-pollution-guarded
  ///   (`__proto__`/`constructor`/`prototype` keys rejected at any depth,
  ///   ported verbatim from upstream).
  /// - reject: feeds a refusal tool result back; the model continues.
  /// Throws StateError on unknown id, expired id, or replay (consume-once).
  Future<void> resume(String id, FmInterruptDecision decision,
      {Map<String, Object?>? editedArgs});
}

/// Consume-once registry. Replay protection is by consumed-id tombstone,
/// not by deletion: resuming a consumed or expired id throws StateError.
abstract class FmInterruptRegistry {
  FmInterrupt register(FmInterrupt interrupt);
  FmInterrupt consume(String id); // throws on unknown/expired/consumed
}

/// Intent router (port of classifyRouteIntent).
final class FmIntentRouter {
  FmIntentRouter({required FoundationModels runtime,
      required Map<String, String> routes}); // routeId -> description
  /// Returns the route id for [input] via guided classification; always one
  /// of the registered ids (enum-constrained), or the configured fallback.
  Future<String> classifyRouteIntent(String input, {String? fallbackRoute});
}

/// Optional MCP adapter.
final class FmMcpClient {
  static Future<FmMcpClient> connectStdio({required String command,
      List<String> args = const []});
  static Future<FmMcpClient> connectHttp(Uri base,
      {Map<String, String>? headers});
  /// MCP tool definitions adapted to callback tools (inputSchema sanitized
  /// via SchemaMode.tool).
  Future<List<FmTool>> listFmTools();
  Future<void> close();
}
```

### (b) MLX/CoreAI — no new types; behavioral contract on existing surface

```dart
// Existing parameter, now documented for backend ids:
Future<FmResponse> respond({..., String model = 'apple.system'});
//   'apple.system'      — system model (default path, full feature set)
//   'apple.mlx:<id>'    — MLX backend via U8 (direct path, restricted)
//   'apple.coreai:<id>' — CoreAI backend via U8 (direct path, restricted)

// Local restriction enforced in FoundationModels.respond/stream before the
// channel (new validation block):
//   if (model starts with 'apple.mlx:' or 'apple.coreai:') and
//      (tools != null || unsupportedContextOptionsPresent)
//     throw UnsupportedOptionException(options: ['tools', ...]);
```

## Work items

1. **Agent loop core.** `FmAgent.run` drives `runtime`'s streaming with the
   registered tools: model `tool_call_request` → HITL gate per
   `interruptPolicy` → execute (via the phase-4 duplex path) → feed result →
   repeat until `done`. Translate to AG-UI-shaped events with the exact
   upstream type strings; include `traceId` passthrough when phase-6 tracing
   is installed.
2. **HITL interrupts.** `FmInterruptRegistry` in-memory implementation with
   consume-once tombstones + TTL sweep; unit-test: approve executes, reject
   feeds refusal, edit executes edited args, **replay of a consumed id
   throws**, **expired id throws**, concurrent consume attempts resolve
   exactly once.
3. **editedArgs validation.** Port the upstream prototype-pollution guard
   verbatim (deep key scan rejecting `__proto__`, `constructor`,
   `prototype`; then schema validation against the tool's `inputSchema` in
   `SchemaMode.tool`-sanitized form). Golden tests from upstream fixtures:
   malicious payloads rejected, legitimate deep edits accepted.
4. **Intent router.** `classifyRouteIntent` implemented over
   `FoundationModels.classify` with route descriptions as enum labels;
   deterministic under the mock; fallback route on empty/ambiguous results.
5. **Cancellation mapping.** `CancelToken` cancels the run: loop stops,
   in-flight generation receives `foundationmodels.generation.cancel`,
   pending interrupts are left registered but the run terminates with
   `GenerationCancelledException` semantics; document the AbortSignal →
   CancelToken correspondence (single source: `CancelTokenSource`).
6. **MCP adapter (optional layer).** stdio + HTTP JSON-RPC clients; tool
   listing → `FmTool.callback` adaptation; call forwarding with timeout;
   server errors map to tool error results (`TOOL_CALLBACK_ERROR`) so the
   loop survives flaky MCP servers. Package remains optional — agent kit
   compiles and runs without MCP.
7. **MLX/CoreAI local restrictions.** Implement the model-id check in
   `FoundationModels.respond`/`stream` (and session wrappers): direct-path
   requests with `tools` (or context options the backend rejects, per the
   U8-exposed capability descriptor) throw `UnsupportedOptionException`
   listing the option names **before** any transport call. Keep the check
   data-driven from `capabilities()` where the core reports restrictions, so
   future backend relaxations need no client change.
8. **MLX/CoreAI availability.** Parse U8 capability payloads: registered
   model ids, load state, backend availability; surface through
   `capabilities()` unchanged (pass-through — the adapter never invents
   capability data). Feature-detect guidance in doc comments.
9. **On-device validation.** (a) HITL end-to-end: tool loop pauses, approve
   resumes, edit path with guarded args, reject path continues the loop,
   interrupt expires on TTL. (b) A `respond` with an `apple.mlx:*` model id
   on a Mac with the backend available; verify restriction enforcement
   (tools → typed error) and real generation. Record evidence in
   `docs/parity.md` (`MLX backend`, `CoreAI backend`, and a new
   `Agent kit` row).

## Test plan

### Unit (CI, no Mac)

- Agent loop against `MockProvider` scripted with tool callbacks:
  single-tool and multi-step loops complete; event sequence matches AG-UI
  ordering fixtures.
- Interrupt registry: consume-once, TTL expiry, replay rejection,
  concurrency single-resolution.
- editedArgs guards: upstream fixture set (pollution keys at every depth,
  nested arrays) + schema mismatch rejection.
- Router: enum-constrained output, fallback behavior, mock determinism.
- MLX restrictions: local `UnsupportedOptionException` with `options`
  populated; zero transport traffic on violation.

### Contract (CI, fake transport)

- Full run replayed with recorded envelopes: interrupt → resume(approve) →
  `tools.result` → completion; resume(edit) sends exactly the edited args;
  resume after cancel → StateError, no transport traffic.
- MCP fake server: tool listing adaptation and call forwarding.

### On-device smoke (Apple Silicon)

- Work item 9 (a) and (b); evidence logged (date, device, OS build,
  `swift-core` version, backend ids).

## Acceptance criteria

- [ ] Tool loop completes multi-step runs on device with AG-UI-shaped events
      whose `type` strings match the upstream taxonomy.
- [ ] HITL: approve/edit/reject all work; interrupts are consume-once
      (replay blocked with StateError) and expire on TTL.
- [ ] `editedArgs` pass schema validation and the ported
      prototype-pollution guards (`__proto__`/`constructor`/`prototype`
      rejected at any depth).
- [ ] `classifyRouteIntent` returns registered route ids only, deterministic
      under the mock.
- [ ] `CancelToken` cancels a run cleanly, including mid-interrupt and
      mid-tool-callback.
- [ ] MCP tools (when enabled) adapt into `FmTool`s and survive server
      errors as tool error results; kit works with MCP absent.
- [ ] `apple.mlx:*`/`apple.coreai:*` generate on device post-U8; restricted
      options fail locally with `UnsupportedOptionException`.
- [ ] `capabilities()` reports backend state honestly; `docs/parity.md`
      updated with evidence.
- [ ] CI green without a Mac.

## Estimate

3–5 weeks (matches ADR-0001 §16). HITL correctness (items 2–3) and the U8
dependency for (b) are the critical path; the router, cancellation, and MCP
adapter are parallelizable.
