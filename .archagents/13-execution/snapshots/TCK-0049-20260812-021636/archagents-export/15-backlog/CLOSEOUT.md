# Closeout backlog — finish residual parity gaps

**Created:** 2026-08-11  
**Drain status:** closed 2026-08-11 (RUN-20260811-closeout)  
**Epic:** [TCK-0029](tickets/TCK-0029-epic-finish-parity-closeout.md)  
**Baseline matrix:** [`docs/parity.md`](../../docs/parity.md)  
**Predecessor:** TCK-0018 drain closed with honest partials / not measured / blocked

## Goal of this backlog

Promote every remaining Flutter gap from the post-drain matrix to either:

1. **`supported`** with dual-run host-native or iOS-device evidence, **or**
2. An explicit, permanent product/env limit documented in `docs/parity.md` (never soft-pass).

## Already good (do not re-open)

availability · respond · stream+cancel · sessions · guided · countTokens · feedback · vision OCR+barcode · pure-Dart ecosystem packages · static tools (host measured)

## Open work (ordered)

### Wave A — Apple path completeness (unblocks “agent + chat” quality)

| ID | Prio | Effort | Gap | Done when |
|---|---|---|---|---|
| **TCK-0030** | high | L | Tools **duplex** on host (ToolCallbackBridge in ios-bridge / plugin stream) | dual-run: `tool_call_request` + `tools.result` + content uses callback output → tools cell **`supported`** |
| **TCK-0031** | high | M | Instructions **post-transition content B** (underB) | dual-run: after `transition(instructions: BETA)`, respond content reflects B → instructions cell **`supported`** |
| **TCK-0036** | high | L | Flutter **live** plugin E2E macOS (public Dart API → channels → Core, not bridge-only) | dual-run host app: availability + respond + stream/cancel via `foundationmodels_apple` |

### Wave B — Device + backends

| ID | Prio | Effort | Gap | Done when |
|---|---|---|---|---|
| **TCK-0035** | high | L | **iOS device** FM smokes (attempt; iPad may be available) | dual-run or typed env failure log; fill `apple-on-device-*` evidence rows if success |
| **TCK-0033** | medium | L | **MLX** with registered weights + content path | dual-run respond content + correct model echo, or permanent “no weights” limit |
| **TCK-0034** | medium | L | **CoreAI** monorepo registered model + content | same as MLX; document mirror stub vs monorepo |

### Wave C — Capability honesty / gated

| ID | Prio | Effort | Gap | Done when |
|---|---|---|---|---|
| **TCK-0032** | medium | M | **Multimodal** when a model reports image support | image respond smoke **or** keep partial with capability gate (already measured for apple.system) |
| **TCK-0028** | low | L | **PCC** entitlement U9 | stays **blocked** until entitlement + smoke |

Epic **TCK-0029** closes when A+B+C children are done or permanently limited with notes.

## Optional adjacent (not matrix closeout)

Track only if product needs them; not required for parity cells:

| ID | Item |
|---|---|
| TCK-0038 | Live Unix-socket daemon E2E |
| TCK-0039 | MCP agent client wiring |
| TCK-0040 | Sibling `chat-on-device` integration |
| TCK-0041 | pub.dev publish / remove `publish_to: none` |

## Suggested order

```
1. TCK-0030 tools duplex
2. TCK-0031 instructions transition B
3. TCK-0036 Flutter live plugin E2E
4. TCK-0035 iOS device attempt
5. TCK-0033 / TCK-0034 MLX + CoreAI (needs model registry)
6. TCK-0032 multimodal if/when model supports image
7. TCK-0028 PCC only if entitlement appears
```

## Definition of Done (program)

- [x] Zero `todo` under TCK-0029…0036 (0028 may stay blocked)
- [x] `docs/parity.md` has no soft-pass `supported` cells
- [x] CONTINUATION + plan-board point at residual or “closeout complete”
- [x] Dual pure-Dart + ecosystem green

**Closed:** 2026-08-11 — RUN-20260811-closeout. Optional adjacent TCK-0038…0041 remain deferred.
