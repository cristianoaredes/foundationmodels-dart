---
run_id: RUN-20260811-residual-drain
ticket: TCK-0016
status: completed
test_result: pass
---

# RUN-20260811-residual-drain

Closed residual tickets TCK-0004, TCK-0016, TCK-0017.

## Smokes (host-native Apple Intelligence)

- MacBook Pro M5 Pro, macOS 27.0 (26A5388g), Xcode 27
- Bridge: FoundationModelsIOSBridge + FoundationModelsCore
- availability: available=true (apple.system)
- respond: ok (output+usage+traceId)
- stream+cancel: deltas then terminal error after cancelGeneration

## Mirror

- Published https://github.com/cristianoaredes/foundationmodels-swift tag v1.0.0
- Vendored Core+Bridge sources as single SPM package

## Evidence

- scratch smoke-respond.log / smoke-stream-cancel.log
- docs/parity.md evidence log
