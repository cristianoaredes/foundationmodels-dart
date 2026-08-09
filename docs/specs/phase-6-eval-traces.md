# Phase 6 — Eval harness + traces

Implementation spec for ADR-0001 §16 phase 6 ("Eval + traces"): a port of
`@orqo/foundationmodels-eval` — datasets, scorers, runs, reports — plus the
trace contract (`traceId` end-to-end, inspectable) the harness depends on.

## Goal

Teams can define eval datasets, run them against any `FmProvider` (mock in
CI, real model on device), score outputs with deterministic and model-based
scorers, and inspect every run through end-to-end traces: one `traceId`
threads from the public API call through the provider into stream events and
responses, and is queryable afterwards. Reports are reproducible artifacts
(JSON + Markdown) recorded next to `docs/parity.md` evidence.

## Depends on

- Phases 1–3 (runtime, streaming, sessions, guided generation, mock).
- Trace surface already partially present: `FmResponse.traceId`
  (`foundationmodels/lib/src/provider.dart`), `FmStreamEvent.traceId`
  (`platform_interface/lib/src/events.dart`), `StreamDone.usage`.
- Upstream `@orqo/foundationmodels-eval` for scorer inventory, dataset
  format, and report shapes (port, do not reinvent).

## Scope

### In

- New package `packages/foundationmodels_eval/` (pure Dart, no Flutter;
  `dart:io` only for dataset/report file helpers).
- Trace plumbing completion: providers must propagate/emit `traceId`
  end-to-end (mock currently emits none — see "Known gap"); a `FmTraceSink`
  inspection contract.
- Dataset model + JSONL loader; case fields mirror upstream (input,
  instructions, schema, expected, tags).
- Scorer port: deterministic scorers (exact match, JSON-schema validity,
  contains/regex, latency budget, token budget) + LLM-judge scorer
  (model-graded, using the runtime itself; marked `estimated` in reports).
- Run engine: concurrency-limited execution over a dataset against a
  `FoundationModels` runtime, per-case results with traces attached,
  deterministic under the mock (same dataset + same mock → identical
  scores).
- Reports: machine-readable JSON + Markdown summary (scores per scorer,
  per tag; failures listed with trace ids for inspection).
- CI wiring: eval suite against the mock; on-device eval run recorded as
  evidence.

### Out

- Eval UI/dashboards (reports are files; no web UI).
- Online/continuous eval infra.
- Changes to upstream eval semantics — this is a port with Dart-idiomatic
  naming only.

## Known gap to close first

`MockProvider` never sets `traceId` on responses or stream events, and
`TransportProvider._toResponse` only reads `traceId` when the core returns
it. The trace contract requires: (1) the runtime mints a `traceId` per
public API call when the provider did not supply one (format `trc_...`,
same minting style as `FoundationModels._newId`); (2) the minted id travels
into `FmRequest`-scoped trace recording; (3) the mock emits deterministic
trace ids (derived from the request hash — never random) so CI eval runs
are reproducible.

## API deltas

```dart
// packages/foundationmodels_eval/lib/src/trace.dart
/// One recorded span of a generation call (request, events, terminal).
final class FmTrace {
  final String traceId;          // end-to-end id, e.g. "trc_..."
  final String requestId;
  final String? sessionId;
  final String method;           // "respond" | "stream" | "extract" | ...
  final DateTime startedAt;
  final Duration? duration;
  final Usage? usage;            // estimated flag preserved
  final List<FmStreamEvent> events; // empty for unary
  final Object? result;          // text or structured (never rawContent of errors)
  final FoundationModelsException? error;
}

/// Receives completed traces. The runtime writes here when a sink is
/// configured; the eval harness installs one per run.
abstract class FmTraceSink {
  void record(FmTrace trace);
}

/// In-memory sink with query-by-traceId inspection.
final class FmInMemoryTraceSink implements FmTraceSink {
  List<FmTrace> get traces;
  FmTrace? byId(String traceId);
}

// packages/foundationmodels_eval/lib/src/dataset.dart
final class FmEvalCase {
  final String id;
  final String input;
  final String? instructions;
  final FmSchema? schema;        // from package:foundationmodels
  final Object? expected;        // scorer-specific ground truth
  final List<String> tags;
}

final class FmEvalDataset {
  final String name;
  final List<FmEvalCase> cases;
  static FmEvalDataset fromJsonl(String source); // one case per line
}

// packages/foundationmodels_eval/lib/src/scorers.dart
abstract class FmScorer {
  String get id;
  Future<FmScore> score(FmEvalCase test, FmTrace trace);
}

final class FmScore {
  final String scorerId;
  final double value;            // normalized [0, 1]
  final bool pass;
  final String? reason;
}

// Ported deterministic scorers (upstream inventory):
// ExactMatchScorer, SchemaValidScorer (validates trace.result against the
// case's FmSchema), ContainsScorer, RegexScorer, LatencyBudgetScorer,
// TokenBudgetScorer.
// Model-graded: LlmJudgeScorer({required FoundationModels runtime, ...}) —
// scores via a guided-generation classify; reports carry
// "estimated": true for judge-graded rows.

// packages/foundationmodels_eval/lib/src/run.dart
final class FmEvalRunner {
  FmEvalRunner({required FoundationModels runtime, List<FmScorer>? scorers,
      int concurrency = 1, FmTraceSink? traceSink});

  /// Executes [dataset], scoring every case with every scorer.
  /// Deterministic when [runtime] is mock-backed.
  Future<FmEvalRun> run(FmEvalDataset dataset);
}

final class FmEvalRun {
  final String id;               // "run_..."
  final DateTime startedAt;
  final List<FmEvalCaseResult> results;
  Map<String, Object?> toJson(); // machine-readable report
  String toMarkdown();           // summary table + failures with traceIds
}
```

Runtime additions in `package:foundationmodels` (minimal, additive):

```dart
// createFoundationModels gains an optional trace sink:
Future<FoundationModels> createFoundationModels({
  List<FmProvider>? providers,
  SecurityConfig? security,
  ContextPolicy? contextPolicy,
  FmRuntimeConfig? config,   // phase 3
  FmTraceSink? traceSink,    // NEW (lives in platform_interface to avoid cycles)
});

// FoundationModels gains:
String? get lastTraceId; // convenience for ad-hoc inspection
```

`FmTrace`/`FmTraceSink` are defined in
`packages/foundationmodels_platform_interface` (they reference
`FmStreamEvent`, `Usage`, `FoundationModelsException`), keeping
`foundationmodels_eval` a consumer, not an owner, of the contract.

## Work items

1. **Trace contract types.** Add `FmTrace`/`FmTraceSink` to the platform
   interface; document that traces never carry `rawContent` (same invariant
   as errors).
2. **Runtime trace plumbing.** `FoundationModels.respond`/`streamInSession`
   (and session wrappers) build an `FmTrace`: mint `trc_...` when the
   provider reports no `traceId`; capture method, timing, events (stream),
   usage, terminal result/error; emit to the configured sink in a `finally`.
   Keep zero overhead when no sink is installed (null-check, no buffering).
3. **Mock trace determinism.** `MockProvider` derives `traceId` from the
   request hash (`trc_<fnv1a-hex>`); same request → same trace id.
4. **Dataset loader.** JSONL parsing with schema-name registry for
   guided-generation cases (schemas referenced by name in the dataset,
   supplied by the caller — JSONL stays serializable).
5. **Deterministic scorers.** Port the upstream inventory exactly (same
   pass/fail thresholds); `SchemaValidScorer` reuses the phase-3 local
   schema validator against `trace.result`.
6. **LLM judge.** `LlmJudgeScorer` prompts the runtime with a guided
   classify schema (`FmSchema.string(enumValues: [...])`); its own
   generations are traced too but excluded from the case's score inputs;
   reports mark judge rows `estimated: true`.
7. **Run engine.** Sequential by default (`concurrency: 1`) to respect
   `SESSION_BUSY` semantics on device; per-case isolation (fresh session per
   case unless the case opts into a shared session); failures recorded as
   results with `error` + `traceId`, never aborting the run.
8. **Reports.** `toJson` (full fidelity: config, dataset hash, per-case
   scores, traces by reference) and `toMarkdown` (score table by scorer and
   tag, failure list with trace ids). Deterministic dataset hash (content
   hash, same style as the mock's FNV-1a) for reproducibility claims.
9. **CI + device wiring.** `packages/foundationmodels_eval/test/` runs a
   fixture dataset against the mock in CI — identical scores across runs
   (golden report test). On device: run the same dataset against the real
   provider, store the report under `docs/evals/` with date/device/core
   build, and reference it from `docs/parity.md` (`Eval harness + traces`
   row → `supported` on evidence).
10. **Inspection path.** Document and test the flow: report failure →
    `traceId` → `FmInMemoryTraceSink.byId` (or the JSON report's trace
    section) → full event list for the failed case.

## Test plan

### Unit (CI, no Mac)

- Trace plumbing: unary and streaming calls produce exactly one `FmTrace`
  with matching `traceId` across response/events; error calls record the
  typed exception; no sink → no work (guarded).
- Mock trace ids deterministic; distinct requests → distinct ids.
- Every scorer against fixed fixtures, including edge cases (empty output,
  schema-invalid structured content, latency over budget).
- Runner: dataset order preserved, per-case isolation, failing case does not
  abort the run, mock-backed run is byte-identical across two executions.

### Contract (CI, fake transport)

- `traceId` supplied by the transport is preferred over the runtime-minted
  one; absent → minted; stream events carrying a different `traceId` are
  still recorded (mismatch visible in the trace, never silently dropped).

### On-device smoke (Apple Silicon)

- One full eval run against the real provider with at least one guided-
  generation case and one streaming case; report stored; a failure
  deliberately induced (budget scorer with tiny budget) and inspected by
  trace id end-to-end.

## Acceptance criteria

- [ ] `traceId` threads from public API through provider into events and
      `FmResponse` on all providers; mock ids deterministic.
- [ ] `FmTraceSink` receives exactly one trace per call, including error
      calls; traces never contain `rawContent`.
- [ ] Dataset/scorer/runner port matches upstream semantics; deterministic
      scorers unit-tested; judge rows marked estimated.
- [ ] Mock-backed eval runs are fully reproducible (golden report test in
      CI).
- [ ] Reports: JSON (full fidelity) + Markdown (scores, failures with trace
      ids).
- [ ] On-device eval run recorded under `docs/evals/` and referenced from
      `docs/parity.md` (`Eval harness + traces` → `supported` with evidence).
- [ ] CI green without a Mac.

## Estimate

2–3 weeks (matches ADR-0001 §16). Trace plumbing (items 1–3) unblocks the
harness; scorers and runner are pure Dart and parallelizable.
