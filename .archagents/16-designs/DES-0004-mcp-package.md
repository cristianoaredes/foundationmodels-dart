# DES-0004 — MCP package (`foundationmodels_mcp`)

- **Status:** frozen for Stage 1 (TCK-0055)  
- **Date:** 2026-08-11  
- **Implements:** TCK-0053  
- **Parent:** DES-0003 / TCK-0054  

## Decisions (frozen)

| Topic | Decision |
|-------|----------|
| **Role** | **MCP server** — exposes FM capabilities to an MCP host (Cursor/Claude/etc.) |
| **Transport v1** | **stdio** — newline-delimited JSON-RPC 2.0 messages |
| **Package** | `foundationmodels_mcp` · `publish_to: none` · workspace member |
| **Runtime** | `FoundationModels` injected (mock by default; Apple optional later) |
| **Tools** | MCP `tools/list` + `tools/call` map to registered `FmTool` callbacks +/or thin wrappers over `fm.respond` |
| **FmAgent** | **Stays separate** — AG-UI tool loop; not renamed or replaced |
| **SSE / HTTP** | Out of Stage 1 |
| **pub.dev** | Out of Stage 1 |
| **Matrix parity** | MCP path does **not** promote Apple cells to `supported` |

## Protocol subset (v1)

Server handles:

1. `initialize` → protocol version + server info + capabilities `{ tools: {} }`  
2. `notifications/initialized` (ignore / ack)  
3. `tools/list` → tools from registry  
4. `tools/call` → execute tool or built-in `fm_respond`  
5. `ping` (optional)  

Unsupported methods → JSON-RPC `-32601` with `data.code = METHOD_NOT_FOUND`.

Message framing: **one JSON object per line** (NDJSON), UTF-8.

## Security

1. `instructions` is a **trusted channel** — never paste MCP tool args/results or user blobs into `instructions`.  
2. No silent cloud; mock if no provider.  
3. Typed errors via JSON-RPC error + optional `data.code`.  

## Non-goals

- Full MCP resources/prompts/sampling surface  
- Replacing `foundationmodels_agent`  
- Live Apple smoke as DoD blocker  
- Hosted pub.dev package  

## Test plan

- Dual-run mock: `initialize` → `tools/list` → `tools/call` (`fm_respond`) → text result  
- Unknown method fail-closed  
