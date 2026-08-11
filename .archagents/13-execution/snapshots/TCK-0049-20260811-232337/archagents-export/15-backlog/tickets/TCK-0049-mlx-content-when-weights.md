---
id: TCK-0049
slug: mlx-content-when-weights
title: "MLX — content dual-run when model weights registered"
status: blocked
priority: low
effort: L
program: OPEN-BACKLOG
repo_only: true
reaffirmed_at: 2026-08-11T22:00:00-03:00
run: RUN-20260811-l3-open-drain
unblock_when: "MLX model weights registered; apple.mlx:* not MODEL_NOT_FOUND"
---

# TCK-0049 — L3 reaffirm

**BLOCKED** reaffirmed **2026-08-11** (L3 open drain):

- No registered MLX weights on this machine.  
- Content dual-run not executable.  
- Fail-closed behavior still correct (TCK-0033 permanent limit).  

```text
SMOKE mlx env_limit=true reason=no_registered_weights reaffirmed=2026-08-11
```

Unblock when weights + Core registry available → dual-run + parity update.
