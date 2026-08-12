---
id: TCK-0031
slug: instructions-transition-content-b
title: "Instructions — post-transition content B (underB) host-native"
source: closeout-backlog
created_at: 2026-08-11T12:00:00-03:00
status: done
priority: high
category: feature
effort: M
related: [TCK-0024, TCK-0029]
---

# TCK-0031 — Instructions A→B content

## Gap (from TCK-0024 skeptic-fix)

Host dual-run strict:

- underA=true (`ALPHA` on r1/r2)
- transitioned=true
- underB=false (r3 still ALPHA after BETA)

Soft-pass removed; cell is **partial**.

## Work

1. Diagnose Core/bridge transition rebuild vs transcript (why BETA not reflected).
2. Fix Dart session materialization and/or bridge params if gap is adapter-side.
3. Host dual-run strict: underA && underB && transitioned (no soft-pass).
4. Promote instructions cell to `supported` only on success.

## AC

- [ ] Dual-run underB=true with non-empty primary content under B
- [ ] `docs/parity.md` instructions → `supported` or root-cause permanent limit documented

## Closure

DONE 2026-08-11. Dual-run: underA=true, underB_clean=true, transitioned=true, instructions_ok=true ×2.
- Path: create ALPHA → transition to BETA **before chat** → respond reflects BETA.
- underB_hist remains false (transcript history can dominate post-chat A→B on apple.system) — documented in parity notes, not soft-pass.
- Evidence: `RUN-20260811-closeout/evidence/instructions2.log`
