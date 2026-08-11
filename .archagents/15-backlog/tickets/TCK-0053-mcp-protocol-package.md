---
id: TCK-0053
slug: mcp-protocol-package
title: "Optional — MCP protocol client package over FoundationModels"
source: next-wave-intake
created_at: 2026-08-11T21:00:00-03:00
status: todo
priority: low
category: feature
effort: L
related: [TCK-0046, TCK-0039, foundationmodels_agent]
program: NEXT-WAVE
order: 7
wave: C
executable_now: false
product_opt_in: true
unblock_when: "Explicit product request to ship MCP (not just agent tools)"
---

# TCK-0053 — MCP protocol package

## Gap

TCK-0039 closed: **won't ship MCP** in residual-optin; `foundationmodels_agent` is AG-UI-shaped tool loop, not MCP. This ticket is the **design-ready reopen** if product wants real MCP.

## Product opt-in gate

Do **not** start implementation until operator says e.g. “implement MCP” / “ship TCK-0053”.  
Default: leave `todo` low priority.

## Depends on

- Stable `foundationmodels` stream + tools duplex (already)  
- Spec choice: which MCP transport (stdio / SSE) and SDK  

## Work (when product opts in)

1. **Spec spike (half-day):** MCP server vs client role; map tools ↔ FM tools; security (instructions channel).  
2. New package e.g. `foundationmodels_mcp` with `publish_to: none`.  
3. Mock FM path: list tools, call tool, stream text.  
4. Optional live Apple path smoke.  
5. Tests dual-run; docs: “not matrix parity”.  
6. Do not rename agent package as MCP.

## AC

- [ ] Written mini-spec in ticket or DES-NNNN  
- [ ] Package + tests green on mock  
- [ ] Explicit non-claim: not Apple matrix `supported`  
- [ ] Or: product declines → status `cancelled` with note  

## Evidence template

```text
SMOKE mcp mock tools_list_ok call_ok
SMOKE mcp dual_run_ok=true
```

## Files likely to touch

- `packages/foundationmodels_mcp/**` (new)  
- workspace `pubspec.yaml`  
- README ecosystem section  

## Out of scope

- Replacing `foundationmodels_agent`  
- Cloud MCP gateways  

## Design sketch (ready)

```
MCP host/client
    → foundationmodels_mcp
        → FoundationModels (mock | apple transport)
            → tools duplex / stream
```

Security: never paste untrusted MCP tool output into `instructions`.
