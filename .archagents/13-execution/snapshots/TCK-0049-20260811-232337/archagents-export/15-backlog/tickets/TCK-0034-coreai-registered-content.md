---
id: TCK-0034
slug: coreai-registered-content
title: "CoreAI — monorepo registered model + content dual-run"
source: closeout-backlog
created_at: 2026-08-11T12:00:00-03:00
status: done
priority: medium
category: feature
effort: L
related: [TCK-0022, TCK-0029]
---

# TCK-0034 — CoreAI content path

## Gap

Fail-closed without registration; published mirror stubs CoreAI. Cell **not measured**.

## Work

1. Measure only via monorepo `FOUNDATIONMODELS_SWIFT_PATH`.
2. Register `apple.coreai:*` if OS provides; dual-run content.
3. Keep mirror fail-closed documented.
4. Promote only with monorepo evidence labeled clearly.

## AC

- [ ] Content dual-run **or** permanent env/product limit in parity.md

## Closure

DONE 2026-08-11 as **permanent product limit** on distribution mirror.
- Dual-run fail-closed `MODEL_NOT_FOUND` without registered CoreAI model.
- foundationmodels-swift v1.0.2 stubs CoreAI for stable SPM `from:`; full CoreAI via monorepo `FOUNDATIONMODELS_SWIFT_PATH`.
- No silent system fallback.
