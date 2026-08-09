# Parity matrix — foundationmodels-dart vs. upstream

Mirrors the upstream
[`docs/parity.md`](https://github.com/cristianoaredes/foundationmodels-js)
capability rows, with a `Flutter status` column. Discipline inherited from
upstream: **never report a capability as supported unless it uses the native
Apple API or documents a precise fallback** — every `supported` cell requires
on-device evidence (smoke + date + device + core build).

> **All Flutter cells are `not measured`** — on-device measurement is pending
> the phase listed in the roadmap (ADR-0001 §16). "Upstream status" reflects
> the upstream matrix at the time this file was written; re-sync when the
> upstream matrix changes.

| Capability (upstream row) | Upstream status | Flutter status | Target phase | Notes |
|---|---|---|---|---|
| Availability (`availability` + reasonCodes) | supported | not measured | 0 | Routed today; bridge method exists |
| Text generation (`respond`) | supported | not measured | 0 | Bridge method exists (unary) |
| Streaming + cancel | supported | not measured | 2 | Requires U1 + U6 (bridge surface) |
| Sessions (lazy, TTL 30 min, LRU 256, `transition`, `prewarm`) | supported | not measured | 3 | Requires U5 for transition/prewarm/history |
| Instructions (first-request-wins precedence) | supported | not measured | 3 | Semantics inherited from core; documented in Dart API |
| Guided generation (JSON Schema subset → `DynamicGenerationSchema`) | supported | not measured | 3 | `FmSchema` fails fast locally on out-of-subset keywords |
| Multimodal (path/base64, allowlist, EXIF, `label`) | supported | not measured | 3 | Dart only forwards; enforcement stays in core |
| `countTokens` / context overflow (`contextSize`, `tokenCount`) | supported | not measured | 3 | Requires U2 |
| Feedback attachment | supported | not measured | 3 | Requires U4 |
| Semantic index (local RAG) | supported | not measured | 5 | Pure-logic port; embeddings strategy TBD (ADR-0001 §18.6) |
| Security / redaction (policy `off`/`log-only`/`auto` + audit) | supported | not measured | 3 | Port of `foundationmodels-policy` as optional Dart package |
| Eval harness + traces | supported | not measured | 6 | Port of `@orqo/foundationmodels-eval` |
| MLX backend (`apple.mlx:*`) | supported | not measured | 7 | Runs in core today; requires U8 (bridge surface) |
| Tool calling (duplex + native + static) | supported | not measured | 4 | Requires U7; stream-only enforcement done locally in Dart |
| PCC inference | blocked (Apple entitlement) | not measured | gated (U9) | `com.apple.developer.private-cloud-compute`; availability/quota without it |
| CoreAI backend (`apple.coreai:*`) | supported | not measured | 7 | Requires U8 |
| Vision tools (OCR / barcode) | supported | not measured | 3 | Requires U3 |
| Dynamic profiles / Spotlight tool | partial | not measured | 3 | `profile` travels as envelope metadata — automatic parity |

## Evidence log

_No on-device measurements yet. First evidence entries are expected in phase 0
(acceptance: real `respond("Hello")` on an iOS 27+ device), recorded here with
smoke name, date, device, OS build, and `swift-core` version._
