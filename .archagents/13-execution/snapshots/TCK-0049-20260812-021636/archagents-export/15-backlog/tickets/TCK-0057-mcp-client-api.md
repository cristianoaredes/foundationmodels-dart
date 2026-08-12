---
id: TCK-0057
slug: mcp-client-api
title: "MCP client API — FmMcpClient + listToolsAsFmTools"
source: stage2-mcp-client
created_at: 2026-08-11T20:00:00-03:00
status: done
priority: high
category: feature
effort: M
related: [TCK-0056, TCK-0058, DES-0005]
program: STAGE-2-MCP-CLIENT
repo_only: true
done_at: 2026-08-11T20:30:00-03:00
---

# TCK-0057 — FmMcpClient

## Work delivered

- `packages/foundationmodels_mcp/lib/src/mcp_client.dart`
- `initialize`, `listTools`, `callTool`, `listToolsAsFmTools`, `close`
- Security note: do not inject results into `instructions`
- Loopback dual-run tests against `FmMcpServer` + mock FM

## AC

- [x] Dual-run loopback init → list → call  
- [x] Unknown tool surfaces error  
- [x] Exports from package library  

## Evidence

`mcp_client_test.dart` — `SMOKE mcp_client dual_run_ok=true`
