# foundationmodels

Dart API for **Apple Foundation Models** — the Dart/Flutter adapter of
[`foundationmodels-js`](https://github.com/cristianoaredes/foundationmodels-js)
(ADR-0001). **Pure Dart, no Flutter dependency**: fully testable on the VM
with the deterministic offline mock provider.

```dart
import 'package:foundationmodels/foundationmodels.dart';

final fm = await createFoundationModels(); // sem provider → MockProvider determinístico

final cls = await fm.classify(input: 'I love it', labels: ['positive', 'negative']);

final out = await fm.extract(
  input: 'Paris is in France.',
  schema: FmSchema.object({
    'city': FmSchema.string(),
    'country': FmSchema.string(),
  }),
);

final session = await fm.createSession(instructions: 'Answer concisely.');
await for (final event in session.stream(input: 'One sentence on on-device AI.')) {
  if (event is TextDelta) print(event.delta);
}
await session.dispose();
```

## Highlights

- **Primitives**: `classify`, `extract` (with `strict`/`repair`), `rank`,
  `summarize`, `respond`, `createSession`, `availability`, `capabilities`,
  `countTokens`.
- **`FmSchema`** — typed builder emitting exactly the JSON-Schema subset the
  Swift core accepts. `SchemaMode.output` (default) is **fail-fast** with
  `UnsupportedSchemaTypeException` naming keyword + JSON-Pointer path;
  `SchemaMode.tool` silently strips out-of-subset keywords at the edge
  (upstream nuance: tools sanitize, outputs reject).
- **Lazy sessions** — `createSession` only mints a local `ses_*` id; the
  native session is born on the first `respond`/`stream`; first request's
  instructions win; `transition()` changes instructions preserving the
  transcript; `dispose()` drops it.
- **Streaming + `CancelToken`** — cancelling sends
  `foundationmodels.generation.cancel` (`generationId == requestId`); the
  stream terminates with `GenerationCancelledException`. Only streaming is
  truly interruptible.
- **`ContextPolicy.guard`** — pre-flight `countTokens`; throws
  `ContextOverflowException` locally with the full token breakdown.
  `ContextPolicy.compact` is a documented stub for a later phase.
- **Option validation before any call** — `temperature ∈ [0,1]`,
  `maximumResponseTokens > 0`, sampling (`greedy` / `top_k` / `top_p` with
  `topK > 0`, `probabilityThreshold ∈ (0,1]`, `seed ≥ 0`) — `ArgumentError`
  naming the field.
- **Typed errors** — 1:1 mapping of the stable `error.data.code` via
  `FoundationModelsException.fromError` (re-exported from
  `foundationmodels_platform_interface`).
- **`MockProvider`** — deterministic (hash-seeded), offline, usage always
  `estimated: true`; CI without a Mac.
- **`TransportProvider`** — speaks the protocol-v2 envelope over any
  `FoundationModelsTransport` (the native plugin's transport plugs in here).

## Security invariants (upstream parity)

- `instructions` are a trusted channel: the runtime never concatenates user
  input into them — neither should you.
- Errors never carry raw model content.
- Image allowlist is fail-closed (`SecurityConfig.allowedImageRoots`).
- No silent cloud fallback; the mock never performs network IO.
