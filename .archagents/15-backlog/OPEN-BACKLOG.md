# Open backlog — foundationmodels-dart (repo-only)

**Updated:** 2026-08-11 (post L3 drain + full documentation)  
**Scope:** this monorepo only  
**SoT:** this file + `backlog.csv` + tickets/

## Summary

| Metric | Value |
|--------|--------|
| `todo` | **0** |
| `blocked` | **2** (TCK-0049 MLX, TCK-0028 PCC) |
| `done` | **56** |
| Package v1 | **shippable** on `main` |
| Default branch | `main` only |

## Blocked (external gates)

| ID | Priority | Title | Unblock when |
|----|----------|-------|--------------|
| **TCK-0049** | low | MLX content dual-run | Weights + Core registry |
| **TCK-0028** | low | PCC U9 | Apple entitlement + profile |

## Human SAFETY (not L3)

| Item | Notes |
|------|--------|
| pub.dev Phase 2 | ADR-0002 — real publish needs human confirmation |

## Closed programs (reference)

| Program | Doc | Outcome |
|---------|-----|---------|
| Stage 1 | `STAGE-1-DAEMON-COREAI-MCP.md` | drained |
| Stage 2 MCP client | `STAGE-2-MCP-CLIENT-SSE.md` | drained (incl. TCK-0059 harness) |
| Wave A / residual-optin / closeout | respective MD under this folder | drained |

## When gates open

```text
export FM_MCP_SSE_URL=…          # live MCP (TCK-0059 harness already shipped)
/ops-work TCK-0049               # MLX
/ops-work TCK-0028               # PCC
```

## Full narrative docs

- `docs/PROJECT-STATUS.md`  
- `docs/DELIVERY-LOG.md`  
- `CONTINUATION.md`  
- `README.md`  
