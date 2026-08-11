# Full parity backlog — foundationmodels-dart vs foundationmodels-js

**Created:** 2026-08-11  
**Drain status:** closed 2026-08-11 + skeptic-fix (honest partials; TCK-0028 blocked)  
**Epic:** [TCK-0018](tickets/TCK-0018-epic-full-parity-residual.md)  
**Source of truth for cells:** [`docs/parity.md`](../../docs/parity.md)

## What "full parity" means here

| In | Out |
|---|---|
| Every upstream-`supported` row is Flutter `supported` with smoke evidence **or** honest non-supported with recorded limit | Line-by-line TypeScript port |
| Host-native **and** (where possible) iOS device | Invented `supported` without smoke |
| Flutter public API path (plugin channels), not only bridge HostSmoke | Forcing PCC without entitlement |
| Fail-closed backends (MLX/CoreAI) never silent-fallback | Claiming pure-Dart packages as on-device Apple |

PCC remains **`blocked`** until U9 (TCK-0028).

## Already closed (do not re-open for ceremony)

| Cell | Evidence |
|---|---|
| Availability | host-native 2026-08-11 |
| respond | host-native |
| stream + cancel | host-native dual-run delta→error, RC fail-closed |
| sessions transition/prewarm | host-native |
| guided generation | host-native structured output |
| countTokens | host-native measured tokens |
| feedback | host-native attachmentBase64 |
| vision OCR | host-native texts content |
| pure-Dart ecosystem | policy / rag / eval / agent / tools / server / langchain / daemon auth |

## Residual tickets (priority order)

| ID | Priority | Effort | Gap | Target outcome |
|---|---|---|---|---|
| **TCK-0019** | high | L | Tools static application + duplex bridge | tools → **partial** (static ok; duplex unproven) |
| **TCK-0027** | high | L | Flutter plugin E2E (Dart API → channels → Core) | plugin path evidence for all `supported` rows |
| **TCK-0026** | high | L | iOS device smokes | `apple-on-device-*` evidence |
| **TCK-0024** | medium | M | Instructions first-request-wins host | instructions → **partial** (underA ok; underB fail) |
| **TCK-0020** | medium | L | Multimodal native / capability honesty | multimodal → `supported` **or** solid `partial` |
| **TCK-0021** | medium | L | MLX registered model smoke | mlx → `supported`/`partial` with content |
| **TCK-0022** | medium | L | CoreAI monorepo registered smoke | coreai → measured or honest limit |
| **TCK-0023** | low | S | Vision barcode **content** | barcode content evidence |
| **TCK-0025** | low | M | Session TTL/LRU observe or document | sessions notes honest |
| **TCK-0028** | low | L | PCC entitlement U9 | stays `blocked` until entitled |

Epic: **TCK-0018**.

## Optional / adjacent (not matrix parity)

Not required for matrix full-parity definition; track separately if desired:

- Live Unix-socket daemon E2E
- MCP agent client
- Sibling `chat-on-device` product integration
- pub.dev publication / remove `publish_to: none`
- Dynamic profiles / Spotlight (upstream already `partial`)

## Suggested execution waves

```
Wave 1 (Apple path completeness)
  TCK-0019 tools duplex+static application
  TCK-0027 flutter plugin E2E (macOS)

Wave 2 (device + semantics)
  TCK-0026 iOS device matrix
  TCK-0024 instructions host-native
  TCK-0023 barcode content

Wave 3 (backends + multimodal)
  TCK-0021 MLX registered
  TCK-0022 CoreAI monorepo
  TCK-0020 multimodal honesty

Wave 4 (hygiene / gated)
  TCK-0025 TTL/LRU notes
  TCK-0028 PCC if entitlement appears
```

## Definition of Done (program)

- [x] TCK-0018 children all done or explicitly deferred with reason
- [x] `docs/parity.md` matches evidence log (no invented `supported`)
- [x] CONTINUATION next-work list drained or re-pointed
- [x] Dual pure-Dart + ecosystem tests still green
