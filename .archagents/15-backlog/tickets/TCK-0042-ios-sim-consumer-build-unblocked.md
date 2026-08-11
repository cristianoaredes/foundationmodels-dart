---
id: TCK-0042
slug: ios-sim-consumer-build-unblocked
title: "iOS Simulator — unblock consumer build (upstream Core iOS guards + plugin docs)"
source: consumer-chat-on-device-report
created_at: 2026-08-11T15:00:00-03:00
status: done
priority: high
category: bug
effort: M
related: [TCK-0040, TCK-0044, TCK-0045, TCK-0026, TCK-0035, FND-0009, FND-0010]
consumer: ../chat-on-device
upstream: foundationmodels-swift@1.0.2 (9484ecc)
program: POST-CLOSEOUT
order: 1
---

# TCK-0042 — iOS Simulator consumer build unblock

## Priority in program

**Critical path** of [POST-CLOSEOUT.md](../POST-CLOSEOUT.md) after TCK-0043 (or parallel if ship hygiene deferred).  
Next after this: **TCK-0044** (mirror publish).

## Context

Sibling consumer **chat-on-device** attempted `flutter run` / `flutter build ios --simulator` on **iPhone 17 (iOS 27.0)** with:

```bash
--dart-define=USE_MOCK_LLM=true
```

Mock LLM does **not** skip native compile of `foundationmodels_apple` → Core. Build fails before any Dart smoke.

Operator policy (2026-08-11): fix **in this monorepo / mirror**, not drive-by patches from the consumer session alone.

## Evidence (compile errors — mirror path)

From consumer Xcode build against SPM checkout of  
`https://github.com/cristianoaredes/foundationmodels-swift.git` @ `9484ecc` / `1.0.2`:

1. **SecTask (iOS)**  
   - `Cannot find 'SecTaskCreateFromSelf' in scope`  
   - `Cannot find 'SecTaskCopyValueForEntitlement' in scope`  
   - File: `FoundationModelsCore.swift` (`processPCCEntitlementPresent`)  
   - iPhoneSimulator Security module does not expose SecTask in the public umbrella (macOS-only).

2. **Native vision tools (iOS)**  
   - `Cannot find 'OCRTool' / 'BarcodeReaderTool' in scope`  
   - `nativeVisionTool` — `_Vision_FoundationModels` overlay macOS-only in Xcode 27 beta SDK.

3. **SPM / Xcode 27 beta flake** (secondary)  
   - `NSMutableArray insertObjects:atIndexes:` count mismatch during package graph registration (intermittent).

4. **Monorepo path pitfall (FND-0010)**  
   - Local monorepo Core with CoreAI sources without deps → `CoreAILanguageModels` missing.  
   - Mirror excludes CoreAI (correct for `from:`).

## Definition of Ready

- [x] Repro documented (FND-0009)
- [x] Fix sketch agreed (`#if os(macOS)` fail-closed)
- [x] Touch surfaces: monorepo Core, `third_party/foundationmodels-swift`, plugin README/Package docs
- [ ] Optional DES if effort expands beyond M (default: execute from this ticket + playbook)

## Work

1. Guard `processPCCEntitlementPresent` for non-macOS → `false` (fail-closed).
2. Guard `nativeVisionTool` (OCR/Barcode) for non-macOS → typed unsupported / compile-free path.
3. Apply same guards to monorepo + third_party mirror sources (keep in sync).
4. Document `FOUNDATIONMODELS_SWIFT_PATH`: mirror layout **or** full monorepo with CoreAI deps (FND-0010).
5. Evidence: `flutter build ios --simulator` (example path deps **or** chat-on-device) + log under RUN.

## Acceptance criteria

- [ ] Upstream Core (mirror and/or monorepo) compiles for **iphonesimulator** arm64 without SecTask/OCRTool errors  
- [ ] PCC probe fail-closed on iOS (no macOS-only Security APIs in iOS compile path)  
- [ ] OCR/Barcode fail-closed or unavailable on iOS with typed error (no missing-symbol compile)  
- [ ] Plugin docs: path env contract (mirror vs monorepo+CoreAI)  
- [ ] Evidence log path recorded in RUN + parity notes if needed  
- [ ] Optional: CI job note or workflow for `flutter build ios --simulator`

## Out of scope

- Marking iOS FM generation `supported` (needs AI-capable device — TCK-0035 limit remains)  
- Absolute machine paths in Package.swift  
- pub.dev publish (TCK-0041)

## Implementation sketch

```swift
// processPCCEntitlementPresent
#if os(macOS)
  // SecTaskCreateFromSelf / SecTaskCopyValueForEntitlement
#else
  return false
#endif

// nativeVisionTool
#if os(macOS)
  // OCRTool / BarcodeReaderTool
#else
  throw unsupported(platform: iOS)
#endif
```

## Hand-off

- Findings: FND-0009, FND-0010  
- Unblocks: TCK-0044, TCK-0040  
- Upstream: ship via mirror tag (TCK-0044)

## Closure

DONE 2026-08-11. Core `#if os(macOS)` guards for SecTask PCC + OCR/Barcode. xcodebuild FoundationModelsCore **iphonesimulator BUILD SUCCEEDED** (third_party + mirror tree). FND-0009 closed. chat-on-device full app build hit unrelated Flutter.framework lipo tooling error (not SecTask).
