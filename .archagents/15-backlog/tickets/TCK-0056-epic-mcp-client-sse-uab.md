---
id: TCK-0056
slug: epic-mcp-client-sse-uab
title: "Épico — MCP client + SSE transport (package foundationmodels_mcp)"
source: stage2-mcp-client
created_at: 2026-08-11T20:00:00-03:00
status: done
priority: high
category: feature
effort: L
related: [TCK-0053, TCK-0055, TCK-0057, TCK-0058, TCK-0059, DES-0005]
program: STAGE-2-MCP-CLIENT
repo_only: true
done_at: 2026-08-11T20:30:00-03:00
---

# TCK-0056 — Epic: MCP client + SSE (this repo)

## Goal

Complement Stage 1 **MCP server** (DES-0004) with an **MCP client** and **SSE transport** inside `packages/foundationmodels_mcp`, so hosts can pull remote tools (e.g. UAB) into `FmTool` / agent loops **without** leaving this monorepo’s package boundary.

## Children

| ID | Role | Status |
|----|------|--------|
| [TCK-0057](TCK-0057-mcp-client-api.md) | Client API | done |
| [TCK-0058](TCK-0058-mcp-sse-transport.md) | SSE + loopback transport | done |
| [TCK-0059](TCK-0059-mcp-live-uab-dual-run.md) | Live endpoint dual-run | blocked |

## Closure

**Code done** 2026-08-11: `FmMcpClient`, transports, tests green (server+client suite).  
**Ship:** merge PR containing package sources to `main` (see OPEN-BACKLOG §A).

## Out of scope

Consumer app integration, UI HITL, product dart-defines.
