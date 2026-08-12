# DES-0005 — MCP **client** + SSE (UAB aggregator)

- **Status:** frozen for Stage 2 client track  
- **Date:** 2026-08-11  
- **Parent:** operator product need — consume UAB via SSE  
- **Complements:** DES-0004 (MCP **server** stdio — keep separate)

## Problem

Stage 1 shipped `FmMcpServer` (stdio) so Cursor can call FM.  
Product needs the **opposite**: chat-on-device / FmAgent **consume** tools from **UAB** (MCP aggregator) over **SSE**.

## Decisions

| Topic | Decision |
|-------|----------|
| **Role** | **MCP client** — list/call tools on a remote MCP endpoint |
| **Primary remote** | **UAB** aggregator (product) |
| **Transport v1** | **SSE + JSON-RPC**: outbound `tools/*` via request channel; inbound events via SSE `data:` lines when present |
| **In-process** | `McpLoopbackTransport` — client ↔ `FmMcpServer` without network (CI dual-run) |
| **Package** | Extend `foundationmodels_mcp` (exports client + server); do **not** rename agent |
| **Tool map** | MCP tool → `FmTool.callback` that forwards `tools/call` |
| **Security** | Never paste tool results into `instructions`; fail-open if UAB down |
| **Auth** | Optional `Authorization` header / bearer from config (no secrets in repo) |

## API sketch

```dart
final client = FmMcpClient(transport: transport);
await client.initialize();
final tools = await client.listToolsAsFmTools(); // List<FmTool>
final text = await client.callTool('name', {'arg': 1});
await client.close();
```

## Non-goals

- Full MCP resources/prompts/sampling  
- Replacing DES-0004 server  
- Claiming Apple matrix cells from UAB path  

## Test plan

- Loopback dual-run: client → server mock FM `fm_respond`  
- SSE transport unit: parse `data:` frames + request correlation  
- Unknown tool fail-closed  
