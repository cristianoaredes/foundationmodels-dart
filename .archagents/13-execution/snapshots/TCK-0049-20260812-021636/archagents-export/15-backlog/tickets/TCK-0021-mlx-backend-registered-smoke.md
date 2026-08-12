---
id: TCK-0021
slug: mlx-backend-registered-smoke
title: "MLX backend — register model + measured respond path"
source: full-parity-backlog
created_at: 2026-08-11T04:00:00-03:00
status: done
priority: medium
category: feature
effort: L
related: [TCK-0012, TCK-0018]
---

# TCK-0021 — MLX backend measured

## Gap

Flutter **`not measured`**: unregistered `apple.mlx:*` → typed `MODEL_NOT_FOUND` (good fail-closed). No registered weights / content path.

## Work

1. Register a real MLX model via Core env (`FOUNDATIONMODELS_COREAI_MODELS` / model roots) on monorepo tip.
2. Smoke: `availability` lists model; `respond`/`stream` with `model: apple.mlx:…` returns content; echo model id not silent `apple.system`.
3. Document unsupported options (tools/schema) if Core rejects them.
4. Promote cell only with evidence; else keep `not measured`/`partial` + reason.

## AC

- [ ] Success smoke **or** documented env/product limit under evidence log
- [ ] No silent fallback to system model

## Closure

DONE 2026-08-11: MODEL_NOT_FOUND fail-closed dual-run; no registered weights.
