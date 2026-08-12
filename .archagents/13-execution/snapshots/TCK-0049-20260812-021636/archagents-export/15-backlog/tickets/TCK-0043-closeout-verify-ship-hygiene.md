---
id: TCK-0043
slug: closeout-verify-ship-hygiene
title: "Closeout — VER adversarial + ship hygiene (git materialization)"
source: post-closeout-backlog
created_at: 2026-08-11T16:00:00-03:00
status: done
priority: high
category: chore
effort: S
related: [TCK-0029, TCK-0045]
---

# TCK-0043 — Closeout verify + ship hygiene

## Gap

- RUN-20260811-closeout exists with evidence, but **no** `VER-20260811-closeout` adversarial report.
- Large uncommitted / untracked tree: closeout code + `.archagents/` formalization not on `origin`.
- Without ship hygiene, consumers and future sessions cannot trust “closeout done” beyond local disk.

## Work

1. Write independent VER report under `.archagents/14-verify/reports/VER-20260811-closeout.md`:
   - Evidence paths present and match claims (duplex, instructions, flutter live).
   - Parity cells `supported` have dual-run or honest limit notes (no soft-pass).
   - Dual pure-Dart green (or re-run + cite).
2. Ship checklist (document in RUN or VER):
   - [ ] VER pass
   - [ ] `CONTINUATION` / plan-board / CLOSEOUT / POST-CLOSEOUT consistent
   - [ ] Operator decision: commit + PR (do **not** force-push; no secrets)
3. If operator approves: open PR with closeout + ops artifacts (or record “local-only hold”).

## AC

- [ ] `VER-20260811-closeout.md` exists with pass/fail and evidence citations
- [ ] Explicit ship decision recorded (PR link **or** “hold local” with reason)
- [ ] No parity cell promoted without evidence re-check

## Out of scope

- Implementing TCK-0042 / mirror publish (separate tickets)
- Force-push / rewrite published history

## Depends on

- RUN-20260811-closeout (done)

## Unblocks

- Trust for TCK-0044 publish and external consumers

## Closure

DONE 2026-08-11. VER-20260811-closeout **pass** (evidence duplex/instructions/flutter live present; dual pure-Dart re-run green). Ship: mirror **v1.0.3** published; foundationmodels-dart PR to follow for monorepo materialization.
