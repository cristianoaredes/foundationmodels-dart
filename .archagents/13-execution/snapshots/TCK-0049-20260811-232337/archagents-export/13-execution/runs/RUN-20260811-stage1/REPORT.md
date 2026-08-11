---
run_id: RUN-20260811-stage1
tickets: [TCK-0051, TCK-0050, TCK-0055, TCK-0053, TCK-0054]
status: completed
autonomy: L3
test_result: pass
---

# RUN-20260811-stage1

Stage 1 drain: Daemon · CoreAI · MCP (MLX stays Stage 2).

## Outcomes

| Ticket | Result |
|--------|--------|
| **TCK-0051** | **done** — live binary env_limit reaffirmed (dyld CoreAIRuntime NDArrayDescriptor); fake peer dual-run still green |
| **TCK-0050** | **done** — monorepo layout probe ok; content dual-run not possible without registered AIModel; mirror stub honesty |
| **TCK-0055** | **done** — DES-0004 frozen |
| **TCK-0053** | **done** — `foundationmodels_mcp` package + 4 tests dual-run mock |
| **TCK-0054** | **done** — Stage 1 epic closed |

## Evidence

| File | Notes |
|------|--------|
| `evidence/daemon-probe.log` / `daemon-e2e.log` | exit 134/-6, dyld CoreAI |
| `evidence/coreai-probe.log` | monorepo present; no content dual-run |
| `evidence/mcp-tests.log` | dual_run_ok, failclosed, ndjson |
| DES-0004 | MCP mini-spec |

## Key SMOKE

```
SMOKE live_daemon env_limit=true reason=dyld_coreai_symbol_skew reaffirmed=2026-08-11
SMOKE daemon_e2e dual_run_ok=true
SMOKE coreai env_limit=true reaffirmed=2026-08-11
SMOKE mcp dual_run_ok=true
```

## Honesty

- No Apple matrix cell promoted from daemon/MCP.  
- CoreAI content remains **not measured** until registered model.  
- MLX (TCK-0049) untouched (Stage 2).  
