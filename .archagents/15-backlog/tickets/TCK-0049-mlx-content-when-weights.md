---
id: TCK-0049
slug: mlx-content-when-weights
title: "MLX — content dual-run when model weights registered"
source: stage1-backlog-formalization
created_at: 2026-08-11T21:00:00-03:00
status: blocked
priority: low
category: feature
effort: L
related: [TCK-0033, TCK-0021]
program: OPEN-BACKLOG
stage: content-backends
repo_only: true
executable_now: false
unblock_when: "MLX model weights registered; apple.mlx:* not MODEL_NOT_FOUND"
supersedes_limit_of: TCK-0033
---

# TCK-0049 — MLX content (blocked)

## Gap

Fail-closed without weights (TCK-0033 permanent limit). Content cell not measured.

## When unblocked (this repo)

1. Register MLX via Core env / model root.  
2. Dual-run availability + respond with `model:`; no silent `apple.system` fallback.  
3. Update `docs/parity.md` only with evidence.  

## AC

- [ ] Dual-run content **or** dated reaffirm blocked  
- [ ] No silent system fallback  

## Out of scope

- Bundling weights in git  
- Consumer app UX  
