---
id: TCK-0051
slug: daemon-live-binary-e2e
title: "Daemon — live foundationmodels-daemon binary Unix-socket E2E"
source: next-wave-intake
created_at: 2026-08-11T21:00:00-03:00
status: todo
priority: high
category: feature
effort: M
related: [TCK-0054, TCK-0046, TCK-0038]
program: STAGE-1
stage: 1
order: 1
wave: stage1
executable_now: true
unblock_when: "Probe always executable; full dual-run needs binary exit 0"
---

# TCK-0051 — Live daemon binary E2E (Stage 1 #1)

## Gap

TCK-0038 **done** for **client path** via fake JSON-RPC peer + live `env_limit` note. Stage 1 needs either:

- dual-run against **real** `foundationmodels-daemon`, or  
- dated reaffirmation that binary remains unusable (with probe evidence).

## Status note

Promoted from pure `blocked` → **`todo`**: probe + documentation always executable; live dual-run still **gated** by binary health.

## Phases

### 1a Probe (always)

```bash
# Example path (adjust to monorepo checkout):
FM_DAEMON_BIN=…/foundationmodels-daemon
"$FM_DAEMON_BIN" --help; echo exit:$?
```

Record: path, exit, stderr (CoreAI/dyld?), `live_ok=true|false`.

### 1b Unblock env (if probe fails)

- Rebuild daemon on monorepo tip / fix link  
- Or document permanent host limit (OS skew) without claiming client bug  

### 1c Dart live E2E (if probe ok)

1. Start daemon on temp Unix socket (document flags).  
2. `DaemonSocketTransport.connect` + dual-run health + respond.  
3. Gate tests with env (`FM_DAEMON_BIN` / `FM_DAEMON_SOCKET`); CI keeps fake peer.  
4. No Apple matrix `supported` from daemon-only.

## AC

- [ ] Probe evidence logged under RUN  
- [ ] Dual-run live **or** blocked reaffirm with date + reason (`env_limit`)  
- [ ] Fake peer tests still green  
- [ ] CI does not require live binary  

## Evidence template

```text
SMOKE live_daemon probe exit=… live_ok=…
SMOKE live_daemon_e2e dual_run_ok=true   # if live_ok
# OR
SMOKE live_daemon env_limit=true reason=… reaffirmed=YYYY-MM-DD
```

## Files likely to touch

- `packages/foundationmodels_daemon/test/socket_e2e_test.dart`  
- optional package README  

## Out of scope

- MLX, MCP, CoreAI content path  
- Rewriting daemon protocol  

## Depends on

- TCK-0038 done (regression baseline)  
