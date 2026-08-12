---
id: TCK-0029
slug: epic-finish-parity-closeout
title: "Épico: finish parity closeout (post-drain residuals)"
source: closeout-backlog
created_at: 2026-08-11T12:00:00-03:00
status: done
priority: high
category: feature
effort: L
related: [TCK-0018, TCK-0030, TCK-0031, TCK-0032, TCK-0033, TCK-0034, TCK-0035, TCK-0036, TCK-0028]
---

# TCK-0029 — Finish parity closeout

Parent epic after TCK-0018 drain. Closes remaining **partial / not measured / unattempted** gaps without inventing `supported`.

## Children

| ID | Focus |
|----|--------|
| TCK-0030 | Tools duplex host |
| TCK-0031 | Instructions transition → content B |
| TCK-0036 | Flutter live plugin E2E macOS |
| TCK-0035 | iOS device FM smokes (attempt) |
| TCK-0033 | MLX registered content |
| TCK-0034 | CoreAI registered content |
| TCK-0032 | Multimodal when capable |
| TCK-0028 | PCC (blocked) |

## AC

- [ ] All children done or permanently limited with `docs/parity.md` notes
- [ ] CLOSEOUT.md DoD checked
- [ ] No soft-pass HostSmoke or invented `supported`

## Closure

DONE 2026-08-11. Closeout epic complete: Wave A (0030/0031/0036) measured supported; Wave B/C children done with dual-run evidence or permanent/honest limits; TCK-0028 remains blocked (PCC entitlement).
