---
id: TCK-0030
slug: tools-duplex-toolcallbackbridge
title: "Tools duplex — wire ToolCallbackBridge on ios-bridge + host/plugin smoke"
source: closeout-backlog
created_at: 2026-08-11T12:00:00-03:00
status: done
priority: high
category: feature
effort: L
related: [TCK-0019, TCK-0029]
---

# TCK-0030 — Tools duplex (host Apple)

## Gap (from TCK-0019)

- Static tools host-native: **measured** (`PARITY-42`, toolTokens).
- Duplex host: `tools_duplex_ok=false` (no `tool_call_request`).
- `submitToolResult` without registration correctly fail-closed.
- Mock duplex already green.

## Work

1. Inject `ToolCallbackBridge` (or equivalent) into FoundationModelsIOSBridge stream path (today `toolBridge: nil`).
2. Plugin EventChannel: emit `tool_call_request` / accept `tools.result` (already partially wired on Dart).
3. Host dual-run: callback tool → request event → submit result → final text uses callback payload.
4. Prefer also Flutter public API path (ties to TCK-0036).
5. Promote tools cell to `supported` only with duplex dual-run evidence.

## AC

- [ ] Dual-run duplex primary observable (request + content from tool)
- [ ] `docs/parity.md` tools → `supported` or documented permanent limit
- [ ] No silent double-submit (autoExecuteTools / agent single-executor still holds)

## Closure

DONE 2026-08-11. Host-native dual-run: `tools_duplex_ok=true` (tool_call_request + submitToolResult + content contains `DUPLEX-99`) ×2.
- ios-bridge: inject `ToolCallbackBridge` in `respondStream` with wait/timeout/early-buffer registry; `submitToolResult` completes waiters.
- Evidence: `.archagents/13-execution/runs/RUN-20260811-closeout/evidence/duplex.log`
- Flutter live path also green (TCK-0036).
- Retry: host submit 12× backoff; wait timeout 120s; fail-closed without registration.
