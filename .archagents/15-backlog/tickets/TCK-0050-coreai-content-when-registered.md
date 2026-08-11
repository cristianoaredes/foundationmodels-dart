---
id: TCK-0050
slug: coreai-content-when-registered
title: "CoreAI — content dual-run on monorepo tip when model registered"
status: done
priority: high
effort: L
program: STAGE-1
stage: 1
order: 2
done_at: 2026-08-11T23:30:00-03:00
run: RUN-20260811-stage1
---

# TCK-0050 — Closure

**done** 2026-08-11 (Stage 1) with **env/product limit** (not content `supported`).

- Monorepo `swift/` layout present (Core + ios-bridge).  
- CoreAI modules exist in monorepo build products.  
- **No registered AIModel** for content dual-run on this machine; mirror remains CoreAI-stubbed (`from: "1.0.4"`).  
- Parity: CoreAI content stays **not measured** / fail-closed until model registration.  

Evidence: `RUN-20260811-stage1/evidence/coreai-probe.log`  
Reopen content path only when model registered (new ticket or reopen).
