---
id: TCK-0059
slug: mcp-live-uab-dual-run
title: "MCP client — live dual-run against UAB/SSE endpoint (env-gated)"
status: done
priority: medium
effort: M
program: STAGE-2-MCP-CLIENT
repo_only: true
done_at: 2026-08-11T22:00:00-03:00
run: RUN-20260811-l3-open-drain
---

# TCK-0059 — Closure (L3)

**done** 2026-08-11.

1. Shipped `test/mcp_live_env_test.dart` — dual-run when `FM_MCP_SSE_URL` or `UAB_MCP_URL` set.  
2. Optional `FM_MCP_BEARER`.  
3. Helper `mcpDefaultHttpPost` exported.  
4. **This host:** URL unset →  
   `SMOKE mcp_live skip=no_url env_limit=true reaffirmed=2026-08-11`  

CI stays green without URL. Re-run live anytime by exporting URL.

Evidence: `RUN-20260811-l3-open-drain/evidence/mcp-all-tests.log`
