---
id: TCK-0051
slug: daemon-live-binary-e2e
title: "Daemon — live foundationmodels-daemon binary Unix-socket E2E"
source: next-wave-intake
created_at: 2026-08-11T21:00:00-03:00
status: blocked
priority: low
category: feature
effort: M
related: [TCK-0046, TCK-0038]
program: NEXT-WAVE
order: 6
wave: B
executable_now: false
unblock_when: "Release foundationmodels-daemon exits 0 on --help/health (no dyld CoreAI crash)"
---

# TCK-0051 — Live daemon binary E2E

## Gap

TCK-0038 **done** for **client path** via fake JSON-RPC peer + documented live `env_limit` (exit=-6, CoreAI dyld). Product still lacks dual-run against **real** `foundationmodels-daemon`.

## Unblock gate

```bash
# Must succeed (exit 0) before this ticket is executable:
<path>/foundationmodels-daemon --help
# and/or health over socket after start
```

Root cause to fix is typically **upstream** monorepo build / CoreAI link / OS skew — not Dart client.

## Depends on

- TCK-0038 done (client tests stay green as regression)  
- foundationmodels-js Swift daemon Release build  

## Work (when unblocked)

1. Start real daemon on temp Unix socket (document flags).  
2. Point `DaemonSocketTransport.connect(socketPath:)` at it.  
3. Dual-run health + respond (same assertions as fake peer where applicable).  
4. Keep fake-peer tests; add `live_daemon` group gated by env var e.g. `FM_DAEMON_BIN` / `FM_DAEMON_SOCKET`.  
5. Do **not** mark Apple matrix cells `supported` from daemon-only path.

## AC

- [ ] Dual-run against live binary with evidence log  
- [ ] CI remains green without requiring live binary (skip/gated)  
- [ ] Fake peer tests still pass  
- [ ] Or: reaffirm blocked if binary still env-limited  

## Evidence template

```text
SMOKE live_daemon_e2e run=1 health_ok respond_ok
SMOKE live_daemon_e2e run=2 health_ok respond_ok
SMOKE live_daemon_e2e dual_run_ok=true
```

## Files likely to touch

- `packages/foundationmodels_daemon/test/socket_e2e_test.dart`  
- optional README daemon section  

## Out of scope

- Rewriting daemon protocol  
- Apple plugin parity claims  
