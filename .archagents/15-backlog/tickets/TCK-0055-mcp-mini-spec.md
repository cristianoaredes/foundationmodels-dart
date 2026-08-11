---
id: TCK-0055
slug: mcp-mini-spec
title: "MCP — mini-spec freeze (role, transport, tool map, security)"
source: stage1-backlog-formalization
created_at: 2026-08-11T23:00:00-03:00
status: todo
priority: high
category: chore
effort: S
related: [TCK-0054, TCK-0053, TCK-0039, DES-0003]
program: STAGE-1
stage: 1
order: 3
wave: stage1
executable_now: true
---

# TCK-0055 — MCP mini-spec (Stage 1)

## Gap

TCK-0053 needs a frozen scope before coding. Without this, MCP drifts into “agent rewrite” or multi-transport sprawl.

## Depends on

- None for drafting (DES-0003 sketch exists)  
- Tools duplex + `FmAgent` as **reference** surfaces (already shipped)  

## Work

1. Write mini-spec under `.archagents/16-designs/DES-0004-mcp-package.md` **or** expand this ticket body to final:
   - **Role:** MCP **server** exposing FM tools/prompts to an MCP host (default) vs client-only  
   - **Transport v1:** stdio (document SSE as later)  
   - **Mapping:** MCP tools ↔ `FmTool` / stream tool_call_*; resources optional out of v1  
   - **Runtime:** always `FoundationModels` mock-capable; Apple optional  
   - **Security:** `instructions` trusted channel; untrusted tool/MCP output never into instructions; no silent cloud  
   - **Non-goals:** replace `foundationmodels_agent`; claim Apple matrix parity; pub.dev  
2. Package name proposal: `foundationmodels_mcp` + workspace entry.  
3. Test plan: mock dual-run tools/list + tools/call + text.  
4. Gate: operator OK on defaults if anything ambiguous (stdio server = recommended default).

## AC

- [ ] DES-0004 (or equivalent) checked in with role + transport + non-goals  
- [ ] Explicit: `FmAgent` remains separate product surface  
- [ ] TCK-0053 work section points at frozen decisions  
- [ ] No implementation required in this ticket (spec-only)

## Evidence template

```text
SPEC mcp role=server transport=stdio package=foundationmodels_mcp
SPEC mcp non_goals=agent_replace,matrix_parity,pubdev
```

## Out of scope

- Writing package code (TCK-0053)  
- MLX / CoreAI / daemon  

## Effort

**S** (half-day) if defaults accepted; stop for clarify if role/transport disputed.
