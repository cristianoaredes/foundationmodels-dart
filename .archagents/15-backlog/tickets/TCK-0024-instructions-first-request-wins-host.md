---
id: TCK-0024
slug: instructions-first-request-wins-host
title: "Instructions first-request-wins — host-native proof"
source: full-parity-backlog
created_at: 2026-08-11T04:00:00-03:00
status: done
priority: medium
category: feature
effort: M
related: [TCK-0018]
---

# TCK-0024 — Instructions precedence host-native

## Gap

Flutter **`pure-Dart measured`** only. Upstream row is `supported`.

## Work

1. Host smoke: createSession(instructions A) → first respond → second respond without new instructions → behavior still under A.
2. transition(instructions B) → subsequent respond under B (`transitioned=true` already measured).
3. Promote cell to `supported` only if observable (not just API exists).

## AC

- [ ] Dual-run smoke with primary observable (content/style under A then B)
- [ ] Parity cell updated

## Closure

DONE 2026-08-11 (skeptic-fix): underA=true underB=false dual-run strict (no soft-pass) → parity instructions=partial.
