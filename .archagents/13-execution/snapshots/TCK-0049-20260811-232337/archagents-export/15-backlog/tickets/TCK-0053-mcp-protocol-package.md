---
id: TCK-0053
slug: mcp-protocol-package
title: "MCP protocol package over FoundationModels (Stage 1 implement)"
status: done
priority: high
effort: L
program: STAGE-1
stage: 1
order: 4
done_at: 2026-08-11T23:30:00-03:00
run: RUN-20260811-stage1
---

# TCK-0053 — Closure

**done.** Package `packages/foundationmodels_mcp`:

- `FmMcpServer` — initialize, tools/list, tools/call, fail-closed  
- Built-in `fm_respond` + callback tools  
- NDJSON serve  
- Tests: dual-run mock, METHOD_NOT_FOUND, ndjson e2e (4 pass)  
- Workspace member; `publish_to: none`  

Evidence: `RUN-20260811-stage1/evidence/mcp-tests.log`
