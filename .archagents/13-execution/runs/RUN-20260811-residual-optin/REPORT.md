---
run_id: RUN-20260811-residual-optin
tickets: [TCK-0038, TCK-0039, TCK-0041, TCK-0028]
status: completed
autonomy: L3
test_result: pass
---

# RUN-20260811-residual-optin

L3 drain of residual **product opt-in** backlog after post-closeout (TCK-0045 done).

## Scope

| Ticket | Outcome |
|--------|---------|
| **TCK-0038** | **done** — daemon client Unix-socket dual-run via fake peer; live binary env-limited (dyld CoreAI) |
| **TCK-0039** | **done** — no MCP package; agent/tools honesty + green agent tests |
| **TCK-0041** | **done** — dry-run fails (expected); **ADR-0002 stay-private** |
| **TCK-0028** | **blocked** reaffirmed 2026-08-11 — PCC entitlement U9 |

## Evidence

| Artifact | Result |
|----------|--------|
| `evidence/daemon-socket-e2e.log` | 4 tests pass; dual_run_ok; failclosed missing/unknown; live env_limit |
| `evidence/agent-tests.log` | 7 tests pass (tool loop, HITL, AG-UI events) |
| `evidence/pub-dry-run-*.log` | validation errors → stay-private ADR |
| ADR-0002 | `.archagents/09-decisions/ADR-0002-stay-private-git-only.md` |

## Key SMOKE lines

```
SMOKE daemon_e2e dual_run_ok=true
SMOKE daemon_e2e missing_socket failclosed_ok=true
SMOKE daemon_e2e unknown_method failclosed_ok=true
SMOKE live_daemon env_limit=true reason=dyld_or_cli
```

## Honesty notes

- Daemon E2E validates **shipped Dart client path** (`DaemonSocketTransport`) against
  a protocol-compatible peer. Live `foundationmodels-daemon` binary on this host
  crashes (exit=-6) on CoreAI dyld skew — permanent env limit, not a client bug.
- MCP protocol client is **out of scope / will not ship** in this monorepo wave;
  agent surface is `foundationmodels_agent` (tools duplex + HITL), not MCP.
- Real `dart pub publish` not executed (SAFETY external state).

## Collateral

- iOS plugin: `registrar.messenger()` for current Flutter embedding (unapplied-function fix).
- Docs: pin hygiene mirror **1.0.4** (Package.swift already on 1.0.4; CONTINUATION/plan-board synced).
