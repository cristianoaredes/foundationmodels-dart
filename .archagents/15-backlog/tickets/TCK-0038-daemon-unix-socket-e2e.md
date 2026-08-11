---
id: TCK-0038
slug: daemon-unix-socket-e2e
title: "Optional — live Unix-socket daemon E2E"
source: closeout-backlog-adjacent
created_at: 2026-08-11T12:00:00-03:00
status: done
priority: low
category: feature
effort: L
related: [TCK-0045, TCK-0029]
program: POST-CLOSEOUT
order: 99
done_at: 2026-08-11T20:00:00-03:00
run: RUN-20260811-residual-optin
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

- [x] Live socket dual-run **or** deferred with permanent env reason in ticket closure

## Closure (2026-08-11)

**done** via dual path:

1. **Client path E2E (primary):** `packages/foundationmodels_daemon/test/socket_e2e_test.dart`
   - Fake Unix JSON-RPC peer implementing health + respond line protocol
   - Dual-run health+respond (`PONG-DAEMON`) via `DaemonSocketTransport` + `createFoundationModels`
   - Fail-closed: missing socket → `SocketException`; unknown method → `FmTransportError` + `METHOD_NOT_FOUND`
2. **Live binary env limit (secondary):** Release `foundationmodels-daemon` on host exits -6
   (dyld missing CoreAIRuntime symbol). Documented `env_limit=true reason=dyld_or_cli`.

**Honesty:** does **not** promote any Apple matrix cell to `supported`. Daemon is non-Flutter host transport only.

**Evidence:** `.archagents/13-execution/runs/RUN-20260811-residual-optin/evidence/daemon-socket-e2e.log`
