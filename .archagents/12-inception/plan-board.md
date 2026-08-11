# Plan Board — foundationmodels-dart

| ID | Título | Status |
|----|--------|--------|
| Package v1 | Adapter + tools + agent + server MCP | **shippable on main** |
| Stage 1 | Daemon · CoreAI · MCP server | **done** |
| Stage 2 MCP client | Client + SSE in package | **code done · ship PR** |
| Content backends | MLX / PCC | **blocked** |

## Active formalization

**Source of truth for open work:** [OPEN-BACKLOG.md](../15-backlog/OPEN-BACKLOG.md)

### Ship next (no external gate)

| Ticket | Status | Notes |
|--------|--------|-------|
| TCK-0056 epic MCP client | done | Needs merge to main if not yet |
| TCK-0057 FmMcpClient | done | |
| TCK-0058 SSE transport | done | |

### Blocked (repo-scoped gates)

| Ticket | Gate |
|--------|------|
| **TCK-0059** live UAB MCP dual-run | env URL |
| **TCK-0049** MLX content | weights |
| **TCK-0028** PCC | entitlement |

### Human SAFETY

| Item | Notes |
|------|--------|
| pub.dev Phase 2 | ADR-0002 |

## Next commands

```text
# 1) Ship Stage 2 MCP client package to main (if uncommitted)
# 2) When UAB available:
/ops-work TCK-0059
# 3) Content backends when gates open:
/ops-work TCK-0049
/ops-work TCK-0028
```
