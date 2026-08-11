---
id: TCK-0049
slug: mlx-content-when-weights
title: "MLX — content dual-run when model weights registered (Stage 2)"
source: next-wave-intake
created_at: 2026-08-11T21:00:00-03:00
status: blocked
priority: low
category: feature
effort: L
related: [TCK-0054, TCK-0046, TCK-0033, TCK-0021]
program: STAGE-2
stage: 2
order: 99
wave: stage2
executable_now: false
deferred_reason: "Operator: MLX after Stage 1 (daemon/CoreAI/MCP)"
unblock_when: "Stage 1 epic TCK-0054 done (or explicit override) AND MLX weights registered"
supersedes_limit_of: TCK-0033
---

# TCK-0049 — MLX content path (**Stage 2**)

## Deferral (2026-08-11)

**Not Stage 1.** Operator formalized Stage 1 as daemon + CoreAI + MCP only.  
MLX remains playbook-ready but **parked** until Stage 1 epic closes or explicit override.

## Gap

TCK-0033 closed as permanent product limit without weights. Content cell not measured.

## Unblock gate (all)

1. Stage 1 done **or** operator override  
2. MLX model files + Core registry  
3. `availability` lists `apple.mlx:*` without silent system remap  

## Work (when Stage 2)

(Unchanged) Dual-run content + parity honesty — see original plan in DES-0002 / closeout tickets.

## AC

- [ ] Not started during Stage 1 without override  
- [ ] When pulled: dual-run content **or** reaffirm blocked with date  

## Out of scope Stage 1

Any MLX content work under TCK-0054.
