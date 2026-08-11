---
id: TCK-0054
slug: epic-stage1-daemon-coreai-mcp
title: "Épico Stage 1 — live daemon E2E + CoreAI content + MCP package"
source: stage1-backlog-formalization
created_at: 2026-08-11T23:00:00-03:00
status: todo
priority: high
category: feature
effort: L
related: [TCK-0051, TCK-0050, TCK-0055, TCK-0053, TCK-0046, TCK-0038, TCK-0034, TCK-0039]
program: STAGE-1
stage: 1
---

# TCK-0054 — Epic: Stage 1 (Daemon · CoreAI · MCP)

## Goal

Deliver or honestly close the three Stage 1 tracks:

1. **Live daemon** Unix-socket E2E (or dated env limit)  
2. **CoreAI content** on monorepo tip (or dated env limit)  
3. **MCP** mini-spec + package over FoundationModels (mock-first)  

**Explicitly out of this epic:** MLX (Stage 2 / TCK-0049), PCC, pub.dev publish.

## Children (ordered)

| Order | Ticket | Role | Priority |
|------:|--------|------|----------|
| 1 | [TCK-0051](TCK-0051-daemon-live-binary-e2e.md) | Daemon live E2E | high |
| 2 | [TCK-0050](TCK-0050-coreai-content-when-registered.md) | CoreAI content | high |
| 3 | [TCK-0055](TCK-0055-mcp-mini-spec.md) | MCP mini-spec | high |
| 4 | [TCK-0053](TCK-0053-mcp-protocol-package.md) | MCP implement | high |

## Program DoD

See [STAGE-1-DAEMON-COREAI-MCP.md](../STAGE-1-DAEMON-COREAI-MCP.md).

Epic **done** when all four children are `done` or (for 0050/0051 only) `blocked` with reaffirmation date + evidence; 0055+0053 must not stay “forgotten todo”.

## Pull

```text
/ops-work TCK-0051
```
