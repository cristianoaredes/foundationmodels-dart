---
run_id: RUN-20260811-closeout
ticket: TCK-0029
status: completed
test_result: pass
---

# RUN-20260811-closeout

Drained closeout backlog TCK-0029…0036 (0028 stays blocked; optional 0038–0041 deferred).

## Wave A — measured supported

### TCK-0030 tools duplex (host-native)

- Injected `ToolCallbackBridge` into `FoundationModelsIOSBridge.respondStream`
- Registry: wait / timeout (120s) / early-buffer / cancel / fail-closed submit
- Dual-run: `tool_call_request` → `submitToolResult` → content contains `DUPLEX-99`
- Evidence: `evidence/duplex.log`

### TCK-0031 instructions A→B

- Dual-run: underA=true, underB_clean=true, transitioned=true
- underB_hist remains false (transcript dominance) — documented, not soft-pass
- Evidence: `evidence/instructions2.log`

### TCK-0036 Flutter live macOS E2E

- Public API only: `TransportProvider(createFoundationModelsAppleTransport())`
- Dual-run: availability, respond (PONG), stream+cancel, tools duplex (DUPLEX-99)
- `SMOKE_RC:0`
- Evidence: `evidence/flutter_live_run8.log`
- Fixes landed: Core→protocol event aliases, `generationId` on wire, main-thread EventChannel emit, single Core SPM link, Swift 5 language mode for FlutterResult

## Wave B — honest limits

| Ticket | Resolution |
|--------|------------|
| TCK-0035 | iPad A14 paired; FM unsupported class → not measured with reason |
| TCK-0033 | MLX fail-closed without weights (permanent until registry) |
| TCK-0034 | CoreAI fail-closed / mirror stub (permanent until monorepo registry) |

## Wave C

| Ticket | Resolution |
|--------|------------|
| TCK-0032 | multimodal stays partial (capability gate false for apple.system) |
| TCK-0028 | PCC still blocked |

## Tests

- `packages/foundationmodels_platform_interface` dart test: green
- `packages/foundationmodels` dart test: green

## Device

- MacBook Pro Mac17,9 · Apple M5 Pro · macOS 27.0 (26A5388g) · Xcode 27
- Host-native bridge: monorepo `foundationmodels-js/swift`
- Flutter plugin: monorepo via `FOUNDATIONMODELS_SWIFT_PATH`
