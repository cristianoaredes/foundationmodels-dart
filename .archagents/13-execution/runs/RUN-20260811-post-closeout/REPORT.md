---
run_id: RUN-20260811-post-closeout
ticket: TCK-0045
status: completed
test_result: pass
---

# RUN-20260811-post-closeout

L3 drain of post-closeout program (TCK-0045 children).

## TCK-0043
- VER-20260811-closeout pass
- Dual pure-Dart green (87 foundationmodels tests after generationId test)

## TCK-0042
- Core `#if os(macOS)` SecTask + OCR/Barcode
- xcodebuild FoundationModelsCore iphonesimulator **BUILD SUCCEEDED**
- Evidence: evidence/ios-sim-build.log, mirror-ios-sim-build.log

## TCK-0044
- Published github.com/cristianoaredes/foundationmodels-swift **v1.0.3**
- Plugin Package.swift `from: "1.0.3"`

## TCK-0040
- Consumer path deps OK; package Core unblocked
- Full Runner sim build failed Flutter.framework lipo (tooling) — not SecTask
- Documented partial; package-side AC met

## Corner cases
- Host duplex dual-run SMOKE_RC:0
- Host instructions dual-run SMOKE_RC:0
- Dart: generationId on stream wire; tools duplex mock; autoExecuteTools false
- evidence/apple-smoke.log

## Opt-in
- TCK-0038/39/41 deferred (not product-requested this drain)
- TCK-0028 remains blocked
