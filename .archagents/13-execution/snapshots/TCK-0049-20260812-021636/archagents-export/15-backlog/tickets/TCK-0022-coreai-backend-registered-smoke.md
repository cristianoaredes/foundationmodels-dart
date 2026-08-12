---
id: TCK-0022
slug: coreai-backend-registered-smoke
title: "CoreAI backend — monorepo tip + registered model smoke"
source: full-parity-backlog
created_at: 2026-08-11T04:00:00-03:00
status: done
priority: medium
category: feature
effort: L
related: [TCK-0012, TCK-0015, TCK-0018]
---

# TCK-0022 — CoreAI backend measured

## Gap

Flutter **`not measured`**: fail-closed when unregistered. Published mirror `foundationmodels-swift` 1.0.2 **stubs CoreAI**.

## Work

1. Measure only via monorepo `FOUNDATIONMODELS_SWIFT_PATH` (full CoreAI tip).
2. Register `apple.coreai:*` model if available on host OS; smoke respond.
3. Mirror remains fail-closed stub — document dual distribution path.
4. Promote parity only with monorepo evidence labeled clearly.

## AC

- [ ] Host smoke with real CoreAI **or** honest `not measured` + framework/env reason
- [ ] docs note: mirror ≠ monorepo CoreAI

## Closure

DONE 2026-08-11: MODEL_NOT_FOUND fail-closed dual-run; mirror CoreAI stub.
