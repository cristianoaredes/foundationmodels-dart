---
id: TCK-0053
slug: mcp-protocol-package
title: "MCP protocol package over FoundationModels (Stage 1 implement)"
source: next-wave-intake
created_at: 2026-08-11T21:00:00-03:00
status: todo
priority: high
category: feature
effort: L
related: [TCK-0054, TCK-0055, TCK-0039, foundationmodels_agent]
program: STAGE-1
stage: 1
order: 4
wave: stage1
executable_now: false
depends_on: [TCK-0055]
product_opt_in: true
product_approved_stage1: true
unblock_when: "TCK-0055 mini-spec done"
---

# TCK-0053 — MCP package implement (Stage 1 #4)

## Gap

TCK-0039 closed won't-ship MCP for residual-optin. **Stage 1 product-approved:** ship a real MCP surface as a **new package**, mock-first. Spec frozen in **TCK-0055** / DES-0004.

## Depends on

- **TCK-0055 done** (mini-spec freeze) — hard gate  
- Stable `foundationmodels` stream + tools duplex (already)  

## Work (after 0055)

1. Scaffold `packages/foundationmodels_mcp` + workspace `pubspec.yaml`; `publish_to: none`.  
2. Implement per DES-0004 (default expectation: **MCP server**, **stdio**, tools → `FmTool` / stream).  
3. Mock FM path tests: tools/list, tools/call, text generation dual-run.  
4. README: not matrix parity; not a replacement for `FmAgent`.  
5. Optional: live Apple smoke if machine has FM (do not block DoD).  

## AC

- [ ] Package builds; analyze/tests green on mock  
- [ ] Dual-run mock evidence  
- [ ] Docs: non-claims (parity, agent replace, pub.dev)  
- [ ] Security note: no untrusted content into `instructions`  

## Evidence template

```text
SMOKE mcp mock tools_list_ok call_ok dual_run_ok=true
```

## Files likely to touch

- `packages/foundationmodels_mcp/**` (new)  
- root workspace pubspec  
- README ecosystem section  

## Out of scope

- MLX / CoreAI / daemon  
- pub.dev publish  
- Full SSE multi-transport unless 0055 already locked it  

## Effort

**M–L** after 0055; mock-only DoD keeps it bounded.
