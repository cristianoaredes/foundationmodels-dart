---
id: TCK-0051
slug: daemon-live-binary-e2e
title: "Daemon — live foundationmodels-daemon binary Unix-socket E2E"
status: done
priority: high
effort: M
program: STAGE-1
stage: 1
order: 1
done_at: 2026-08-11T23:30:00-03:00
run: RUN-20260811-stage1
---

# TCK-0051 — Closure

**done** 2026-08-11 (Stage 1).

- **Probe:** Release + Debug `foundationmodels-daemon` → exit 134/-6  
  `dyld: Symbol not found: …CoreAIRuntime…NDArrayDescriptor` (OS CoreAI skew).  
- **Live dual-run:** not possible on this host.  
- **Client path:** fake peer dual-run still green (`socket_e2e_test.dart`).  
- **AC:** env reaffirm with dated evidence ✓  

Evidence: `RUN-20260811-stage1/evidence/daemon-*.log`
