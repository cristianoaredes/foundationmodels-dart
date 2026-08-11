# Stage 2 — MCP **client** + SSE (repo package)

**Created / drained (code):** 2026-08-11  
**Status:** **drained** (code on main + TCK-0059 harness; L3 2026-08-11)  
**Epic:** [TCK-0056](tickets/TCK-0056-epic-mcp-client-sse-uab.md)  
**Design:** [DES-0005](../16-designs/DES-0005-mcp-client-sse-uab.md)  
**Complements:** Stage 1 MCP **server** stdio ([DES-0004](../16-designs/DES-0004-mcp-package.md))

> **Repo scope only.** Consumer wiring (chat-on-device, Orqo UI) is **out of this program**.

## Goal

Extend `foundationmodels_mcp` so this package can **consume** remote MCP tools (e.g. UAB aggregator) via:

1. In-process **loopback** to `FmMcpServer` (CI)  
2. **SSE + JSON-RPC** transport with injectable HTTP (unit-tested)

## Children

| Order | ID | Status | Deliverable |
|------:|----|--------|-------------|
| 1 | TCK-0057 | **done** | `FmMcpClient`, `listToolsAsFmTools`, `callTool` |
| 2 | TCK-0058 | **done** | `McpSseTransport`, `McpLoopbackTransport`, `parseSseDataFrames` |
| 3 | TCK-0056 | **done** | Epic parent |

## Residual (repo-scoped, blocked)

| ID | Title | Gate |
|----|-------|------|
| **TCK-0059** | Live dual-run against real UAB/MCP SSE endpoint | Env URL + network; evidence under RUN |

## Program DoD

- [x] DES-0005 frozen  
- [x] Client + transports implemented  
- [x] `dart test` / analyze green in package  
- [x] Artifacts on `main`  
- [x] TCK-0059 done (env-gated harness + reaffirm when no URL)  

## Evidence (local)

```text
SMOKE mcp_client dual_run_ok=true
SMOKE sse_parse_ok=true
SMOKE sse_transport_post_ok=true
```

## Non-goals

- HITL UI, tool picker, dart-defines in consumer apps  
- Claiming Apple matrix parity via UAB  
- Replacing `FmAgent` or DES-0004 server  
