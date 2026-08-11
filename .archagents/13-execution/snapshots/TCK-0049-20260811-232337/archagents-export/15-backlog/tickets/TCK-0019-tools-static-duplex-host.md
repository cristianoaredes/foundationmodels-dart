---
id: TCK-0019
slug: tools-static-duplex-host
title: "Tools — static application + duplex ToolCallbackBridge on host"
source: full-parity-backlog
created_at: 2026-08-11T04:00:00-03:00
status: done
priority: high
category: feature
effort: L
related: [TCK-0011, TCK-0018]
---

# TCK-0019 — Tools full Apple path

## Gap

Parity row **Tool calling** is Flutter **`partial`**: wire accepts static tools; duplex `submitToolResult` fail-closed without registration; model tool-application not proven on host.

## Work

1. Wire **ToolCallbackBridge** (or equivalent) into FoundationModelsIOSBridge in-process path so stream duplex works.
2. Host smoke: static tool whose **output appears in model answer** (primary: content references tool result, not mere non-empty text).
3. Host smoke: stream + callback tool → `tool_call_request` → `submitToolResult` → continuation / final text.
4. Dart public API path: `stream(..., tools:, autoExecuteTools: true|false)` via plugin when feasible (see TCK-0027).
5. Update `docs/parity.md` → `supported` only with dual-run evidence.

## AC

- [ ] Static tool application smoke dual-run green
- [ ] Duplex smoke dual-run green (or honest env limit logged)
- [ ] Parity cell updated honestly

## Closure

DONE 2026-08-11 (skeptic-fix): static application dual-run; duplex unproven → parity tools=partial.
