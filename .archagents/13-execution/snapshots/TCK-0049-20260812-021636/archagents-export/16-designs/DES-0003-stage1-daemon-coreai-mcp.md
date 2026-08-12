# DES-0003 — Stage 1: Daemon live · CoreAI content · MCP package

- **Status:** approved for execute (operator requested formal backlog)  
- **Date:** 2026-08-11  
- **Epic:** TCK-0054  
- **Program:** [STAGE-1-DAEMON-COREAI-MCP.md](../15-backlog/STAGE-1-DAEMON-COREAI-MCP.md)  
- **Deferred:** MLX → Stage 2 (TCK-0049)

## Context

Package v1 (adapter + tools duplex + agent + consumer sim) is shippable.  
Operator asked to formalize the next backlog covering **daemon, CoreAI, MCP**; **MLX second stage**.

## Alternatives considered

| Option | Pros | Cons | Decision |
|--------|------|------|----------|
| A. Only env-gated tickets (0050/51), skip MCP | Smaller | Leaves MCP informal | Rejected — operator wants MCP in scope |
| B. MCP first (greenfield) | Product surface | Blocks cheap closeouts | Rejected — order daemon→CoreAI→MCP |
| **C. Stage 1 = 0051→0050→0055→0053; MLX stage 2** | Clear DoD, honest gates | MCP still L | **Accepted** |

## Architecture notes

### Daemon

```text
[foundationmodels-daemon binary] --unix-socket--> DaemonSocketTransport
                                                      --> createFoundationModels
Fake peer tests remain CI default; live gated by FM_DAEMON_* env.
```

### CoreAI

```text
unset FOUNDATIONMODELS_SWIFT_PATH  → mirror 1.0.4 (CoreAI stub)  [default]
set monorepo swift/              → CoreAI graph may resolve
respond(model: apple.coreai:*)   → content OR typed fail-closed
Never silent remap to apple.system.
```

### MCP

```text
MCP host (Cursor/Claude/etc.)
  → foundationmodels_mcp (stdio first; SSE later if needed)
      → FoundationModels (mock | apple)
          → tools duplex / stream
FmAgent stays AG-UI tool loop — parallel product surface, not replaced.
```

**Security:** never paste untrusted MCP tool output into `instructions`.

## Risks

| Risk | Mitigation |
|------|------------|
| Daemon binary never fixed | Ticket stays blocked; client E2E already green |
| CoreAI monorepo unusable on CI machine | Document env_limit; no fake supported |
| MCP scope creep | 0055 freezes transport+role; 0053 mock-only DoD |
| MLX sneaks into Stage 1 | TCK-0049 stage=2; epic 0054 excludes MLX |

## Non-goals Stage 1

- MLX weights / content (Stage 2)  
- PCC entitlement  
- Real pub.dev publish  
- Replacing foundationmodels_agent  
