---
id: TCK-0038
slug: daemon-unix-socket-e2e
title: "Optional — live Unix-socket daemon E2E"
source: closeout-backlog-adjacent
created_at: 2026-08-11T12:00:00-03:00
status: todo
priority: low
category: feature
effort: L
related: [TCK-0045, TCK-0029]
program: POST-CLOSEOUT
order: 99
---

# TCK-0038 — Daemon Unix-socket E2E (adjacent)

Not required for Apple matrix or consumer-readiness epic. **Product opt-in.**

## Depends on

- foundationmodels-js daemon runnable on Mac  
- `packages/foundationmodels_daemon` client path

## Work

1. Connect Dart daemon client to live foundationmodels-js Unix socket.
2. Smoke health + respond over real socket (dual-run preferred).
3. Record evidence; do **not** claim Apple matrix `supported` from daemon-only path.

## AC

- [ ] Live socket dual-run **or** deferred with permanent env reason in ticket closure

## When to pull

Only if product needs non-Flutter host integration. Default: leave todo.
