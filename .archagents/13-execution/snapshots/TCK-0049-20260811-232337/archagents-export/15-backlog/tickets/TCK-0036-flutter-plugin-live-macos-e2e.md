---
id: TCK-0036
slug: flutter-plugin-live-macos-e2e
title: "Flutter plugin live macOS E2E — public Dart API → channels → Core"
source: closeout-backlog
created_at: 2026-08-11T12:00:00-03:00
status: done
priority: high
category: feature
effort: L
related: [TCK-0027, TCK-0029, TCK-0030]
---

# TCK-0036 — Live Flutter plugin E2E

## Gap (from TCK-0027)

- Pure-Dart TransportProvider envelopes dual green.
- Live Flutter macOS + `foundationmodels_apple` + Apple FM **not** launched.
- Host-native bridge smokes ≠ full consumer path.

## Work

1. Run `example/` (or integration test) on macOS desktop with Apple Intelligence.
2. Call **only** public `package:foundationmodels` APIs (no direct bridge).
3. Dual-run: availability, respond text non-empty, stream+cancel typed path.
4. Stretch after TCK-0030: tools duplex via public API.
5. Log device/OS + plugin/core version in `docs/parity.md` evidence.

## AC

- [ ] Dual-run live Flutter primary observables
- [ ] Evidence-log lines `flutter-plugin-live-*`

## Closure

DONE 2026-08-11. Live Flutter macOS dual-run via public `package:foundationmodels` API:
- availability dual-run true (apple-transport)
- respond dual-run true (PONG)
- stream+cancel dual-run true (text_delta → GENERATION_CANCELLED)
- tools duplex dual-run true (tool_call_request + callback + DUPLEX-99)
- `SMOKE_RC:0`
- Evidence: `RUN-20260811-closeout/evidence/flutter_live_run8.log`
- Fixes: Core event aliases (delta/text), generationId on wire, EventChannel main-thread emit, plugin single Core link, Swift 5 language mode for FlutterResult.
