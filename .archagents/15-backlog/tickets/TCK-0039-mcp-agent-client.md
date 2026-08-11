---
id: TCK-0039
slug: mcp-agent-client
title: "Optional — MCP agent client wiring"
source: closeout-backlog-adjacent
created_at: 2026-08-11T12:00:00-03:00
status: done
priority: low
category: feature
effort: L
related: [TCK-0045, TCK-0029]
program: POST-CLOSEOUT
order: 99
done_at: 2026-08-11T20:00:00-03:00
run: RUN-20260811-residual-optin
---

# TCK-0039 — MCP agent client (adjacent)

Optional ecosystem surface. **Not** matrix parity. **Not** epic-blocking.

## Work

1. Wire MCP client against mock FM and/or live path.
2. Smoke tool routing + evidence.

## AC

- [x] MCP client smoke with evidence **or** explicit “won’t ship MCP” note

## Closure (2026-08-11)

**done** with honest scope decision:

### Will not ship MCP in this monorepo wave

- Repo-wide search: **zero** MCP protocol package / client (`mcp` / `Model Context` absent).
- Shipped agent surface is **`foundationmodels_agent`**: tool loops, HITL interrupts,
  AG-UI-shaped events, intent router over `FoundationModels.stream` (not MCP).

### Agent / tools dual-path evidence (shipped)

- `packages/foundationmodels_agent` tests: 7 pass
  - tool loop produces tool events + exactly one `tools.result`
  - HITL interrupt → approve path
  - no double-submit when `autoExecuteTools: true` alone
- Related tools duplex already measured on host/plugin closeout (TCK-0030/0036).

**Evidence:** `.archagents/13-execution/runs/RUN-20260811-residual-optin/evidence/agent-tests.log`

Reopen only if product explicitly requests an MCP protocol package (new SPC/TCK).
