---
id: TCK-0052
slug: pubdev-prep-and-optional-publish
title: "pub.dev — package prep (and optional human-gated publish)"
source: next-wave-intake
created_at: 2026-08-11T21:00:00-03:00
status: done
priority: medium
category: feature
effort: M
related: [TCK-0046, TCK-0041, ADR-0002, FND-0007, FND-0008]
program: NEXT-WAVE
order: 3
wave: A
done_at: 2026-08-11T22:00:00-03:00
run: RUN-20260811-wave-a
phase2_status: pending_human
---

# TCK-0052 — pub.dev prep (+ optional publish)

## Closure Phase 1 (2026-08-11)

**done** for prep. Real publish remains human Phase 2.

| Package | LICENSE | CHANGELOG | repository | dry-run errors |
|---------|---------|-----------|------------|----------------|
| platform_interface | ✅ | ✅ | ✅ | **0** |
| foundationmodels | ✅ | ✅ | ✅ | path dep residual |
| foundationmodels_apple | ✅ | ✅ | ✅ | path dep residual |

- `publish_to: none` retained (ADR-0002)  
- Checklist: `.archagents/15-backlog/PUBLISH-CHECKLIST.md`  
- ADR-0002 prep status section updated  

## AC Phase 1

- [x] Checklist table  
- [x] AGPL note (FND-0008 / checklist)  
- [x] publish_to none retained  
- [x] Dry-run improved (platform_interface clean; others documented residual)

## Phase 2

Requires human SAFETY — not done in this run.
