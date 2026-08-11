---
id: TCK-0059
slug: mcp-live-uab-dual-run
title: "MCP client — live dual-run against UAB/SSE endpoint (env-gated)"
source: open-backlog-formalization
created_at: 2026-08-11T24:00:00-03:00
status: blocked
priority: medium
category: feature
effort: M
related: [TCK-0056, TCK-0057, TCK-0058, DES-0005]
program: STAGE-2-MCP-CLIENT
repo_only: true
executable_now: false
unblock_when: "Env UAB_MCP_URL (or FM_MCP_SSE_URL) points to live MCP SSE endpoint; network allowed"
---

# TCK-0059 — Live UAB/MCP dual-run (package only)

## Gap

Loopback + injectable HTTP unit tests prove client/SSE **code**.  
No evidence yet against a **real** remote MCP SSE aggregator.

## Scope (this repo only)

1. Optional test or script gated by env, e.g. `FM_MCP_SSE_URL` + optional `FM_MCP_BEARER`.  
2. Dual-run: `initialize` → `tools/list` → one safe `tools/call` (or skip call if list empty).  
3. Skip cleanly when env unset (CI default).  
4. Evidence log under `.archagents/13-execution/runs/`.  

## Out of scope

- chat-on-device UI / dart-defines product wiring  
- HITL UI  
- Storing secrets in git  

## AC

- [ ] Live dual-run evidence **or** reaffirm blocked with date + reason  
- [ ] CI remains green without live URL  

## Playbook

```bash
export FM_MCP_SSE_URL='https://…'   # when available
# optional: FM_MCP_BEARER=…
(cd packages/foundationmodels_mcp && dart test --name live)  # or dedicated test file
```
