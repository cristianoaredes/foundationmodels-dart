---
id: TCK-0058
slug: mcp-sse-transport
title: "MCP SSE transport + loopback + parseSseDataFrames"
source: stage2-mcp-client
created_at: 2026-08-11T20:00:00-03:00
status: done
priority: high
category: feature
effort: M
related: [TCK-0056, TCK-0057, DES-0005]
program: STAGE-2-MCP-CLIENT
repo_only: true
done_at: 2026-08-11T20:30:00-03:00
---

# TCK-0058 — Transports

## Work delivered

- `packages/foundationmodels_mcp/lib/src/mcp_transport.dart`
  - `McpLoopbackTransport` — in-process client ↔ server  
  - `McpSseTransport` — POST JSON-RPC + optional SSE parse; injectable `httpPost`  
  - `parseSseDataFrames`  
- Unit tests without live network  

## AC

- [x] SSE frame parse  
- [x] Injectable HTTP path  
- [x] Loopback used by client dual-run  

## Evidence

`SMOKE sse_parse_ok=true` · `SMOKE sse_transport_post_ok=true`
