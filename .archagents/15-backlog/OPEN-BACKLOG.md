# Open backlog — foundationmodels-dart (repo-only)

**Updated:** 2026-08-11  
**Scope:** this monorepo only (not chat-on-device / external product UI)  
**Package v1:** shippable on `main` (Stage 1 drained · README current)

## Inventory

### A — Implemented in working tree, needs ship to `main`

| ID | Status | Title | Evidence |
|----|--------|-------|----------|
| **TCK-0056** | done (ship) | Epic: MCP client + SSE | DES-0005 · code under `foundationmodels_mcp` |
| **TCK-0057** | done (ship) | `FmMcpClient` + FmTool adapter | tests dual-run loopback |
| **TCK-0058** | done (ship) | SSE transport + parse frames | unit tests injectable HTTP |

Program: [STAGE-2-MCP-CLIENT-SSE.md](STAGE-2-MCP-CLIENT-SSE.md)  
**DoD for ship:** PR merged with `dart test` green on `packages/foundationmodels_mcp`.

### B — Blocked (playbook ready; no execute without gate)

| ID | Priority | Title | Unblock when |
|----|----------|-------|--------------|
| **TCK-0028** | low | PCC U9 entitlement | Apple entitlement + profile |
| **TCK-0049** | low | MLX content dual-run | MLX weights registered |
| **TCK-0059** | medium | Live UAB MCP dual-run (env-gated) | `UAB_MCP_URL` (or equiv.) reachable; package-only smoke |

### C — Opt-in human / SAFETY (not auto L3)

| Item | Notes |
|------|--------|
| TCK-0052 Phase 2 | Real `dart pub publish` — ADR-0002 + human confirm |
| Daemon live binary | TCK-0051 closed env_limit; reopen only if OS/CoreAI dyld fixed upstream |

## Pull order (when executing)

```text
1. Ship Stage 2 MCP client  (0056–0058)     # no external gate
2. TCK-0059 when UAB URL available          # env-gated package smoke
3. TCK-0049 when MLX weights                # Stage 2 content
4. TCK-0028 when PCC entitlement
5. pub.dev only with human SAFETY
```

## Counts (after formalization)

| Status | Meaning |
|--------|---------|
| done | Closed with evidence (may still need git ship if local) |
| blocked | Gate external to pure coding |
| todo | None required for v1 |

## Related docs

- Plan board: `../12-inception/plan-board.md`  
- Stage 1: `STAGE-1-DAEMON-COREAI-MCP.md` (drained)  
- Stage 2 MCP client: `STAGE-2-MCP-CLIENT-SSE.md`  
- DES-0004 server · DES-0005 client  
