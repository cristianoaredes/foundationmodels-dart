# Open backlog — foundationmodels-dart (repo-only)

**Updated:** 2026-08-11 (L3 drain RUN-20260811-l3-open-drain)  
**Scope:** this monorepo only

## Status after L3 drain

| ID | Status | Notes |
|----|--------|-------|
| TCK-0056…0058 | **done** | MCP client + SSE on main |
| **TCK-0059** | **done** | Env-gated live test; no URL on drain host |
| **TCK-0049** | **blocked** | MLX weights — reaffirmed 2026-08-11 |
| **TCK-0028** | **blocked** | PCC entitlement — reaffirmed 2026-08-11 |

**Zero `todo`.** Executable L3 work exhausted.

## Human SAFETY (not L3)

| Item | Notes |
|------|--------|
| pub.dev Phase 2 | ADR-0002 — real publish needs human |

## When gates open

```text
export FM_MCP_SSE_URL=…   # then: dart test packages/foundationmodels_mcp
/ops-work TCK-0049        # MLX weights
/ops-work TCK-0028        # PCC entitlement
```

## Programs

- Stage 1: `STAGE-1-DAEMON-COREAI-MCP.md` drained  
- Stage 2 MCP client: `STAGE-2-MCP-CLIENT-SSE.md` drained (code + 0059 harness)  
