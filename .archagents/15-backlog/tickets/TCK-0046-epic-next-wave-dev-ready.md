---
id: TCK-0046
slug: epic-next-wave-dev-ready
title: "Épico: next-wave — consumer polish + content backends + gated paths"
source: next-wave-intake
created_at: 2026-08-11T21:00:00-03:00
status: todo
priority: high
category: feature
effort: L
related: [TCK-0045, TCK-0028, TCK-0033, TCK-0034, TCK-0038, TCK-0039, TCK-0041]
program: NEXT-WAVE
---

# TCK-0046 — Epic: next-wave development readiness

## Goal

After residual-optin, formalize and (when unblocked) deliver:

1. Docs path contract (FND-0010)  
2. Full chat-on-device Runner sim path  
3. MLX/CoreAI **content** when weights exist  
4. Live daemon binary E2E when env fixed  
5. pub.dev prep (and optional publish)  
6. Optional MCP package  
7. PCC when entitlement exists  

## Children (ordered)

| Order | Ticket | Wave | Status seed |
|------:|--------|------|-------------|
| 1 | [TCK-0047](TCK-0047-fnd-0010-path-contract-docs.md) | A | todo |
| 2 | [TCK-0048](TCK-0048-chat-on-device-runner-lipo.md) | A | todo |
| 3 | [TCK-0052](TCK-0052-pubdev-prep-and-optional-publish.md) | A/C | todo |
| 4 | [TCK-0049](TCK-0049-mlx-content-when-weights.md) | B | blocked |
| 5 | [TCK-0050](TCK-0050-coreai-content-when-registered.md) | B | blocked |
| 6 | [TCK-0051](TCK-0051-daemon-live-binary-e2e.md) | B | blocked |
| 7 | [TCK-0053](TCK-0053-mcp-protocol-package.md) | C | todo |
| 8 | [TCK-0028](TCK-0028-pcc-u9-entitlement.md) | C | blocked |

## Program DoD

See [NEXT-WAVE.md](../NEXT-WAVE.md). Epic **done** when Wave A complete and Waves B/C either done or explicitly reaffirmed blocked with dated notes.

## Out of scope

- Re-running full matrix closeout  
- Changing license away from AGPL without separate ADR  
