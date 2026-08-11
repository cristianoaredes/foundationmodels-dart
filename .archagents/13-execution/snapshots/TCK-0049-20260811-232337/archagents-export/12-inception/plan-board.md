# Plan Board — foundationmodels-dart

| ID | Título | Status |
|----|--------|--------|
| Package v1 | Adapter + tools + agent + MCP s/c | **shippable** |
| Stage 1 | Daemon · CoreAI · MCP server | **done** |
| Stage 2 MCP client | Client + SSE + live harness | **done** |
| L3 open drain | 0059 done; 0049/0028 reaffirm | **done** 2026-08-11 |

## Remaining (external gates only)

| Ticket | Status | Gate |
|--------|--------|------|
| TCK-0049 MLX content | blocked | weights |
| TCK-0028 PCC | blocked | entitlement |
| pub.dev Phase 2 | human | SAFETY |

## Next

Nothing executable without external gate.  
Live MCP: `export FM_MCP_SSE_URL=… && dart test -C packages/foundationmodels_mcp`
