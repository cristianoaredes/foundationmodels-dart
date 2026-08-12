---
id: TCK-0033
slug: mlx-registered-content
title: "MLX — register model weights + content respond dual-run"
source: closeout-backlog
created_at: 2026-08-11T12:00:00-03:00
status: done
priority: medium
category: feature
effort: L
related: [TCK-0021, TCK-0029]
---

# TCK-0033 — MLX content path

## Gap

Unregistered `apple.mlx:*` → typed `MODEL_NOT_FOUND` (fail-closed measured). Cell **not measured** for content.

## Work

1. Register real MLX model via Core env (`FOUNDATIONMODELS_COREAI_MODELS` / model roots).
2. Dual-run: availability lists model; respond/stream with `model:` key; echo not silent `apple.system`.
3. Document unsupported options (tools/schema) if Core rejects them.
4. Promote cell only with content evidence.

## AC

- [ ] Content dual-run **or** permanent “no weights in this product” note + cell stays not measured

## Closure

DONE 2026-08-11 as **permanent product limit** until weights registered.
- Dual-run fail-closed `MODEL_NOT_FOUND` without registered MLX weights (prior residual drain TCK-0021).
- No content path without registry; no silent system fallback.
- Flutter status stays `not measured` / fail-closed documented (not soft-supported).
