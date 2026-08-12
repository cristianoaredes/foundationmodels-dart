---
id: TCK-0060
slug: ios-macos-platform-floor-gemma-fallback
title: "SPM platform floor (iOS/macOS 27) is app-wide, defeats Gemma OS-version fallback"
source: consumer-chat-on-device-report
created_at: 2026-08-12T10:00:00-03:00
status: raw
priority: medium
category: architecture
effort: unknown
related: [TCK-0042, FND-0009, FND-0011]
consumer: ../chat-on-device
---

# TCK-0060 — SPM platform floor is app-wide, defeats OS-version fallback

## Descrição

`foundationmodels_apple` / `foundationmodels-swift` / `FoundationModelsCore` /
`ios-bridge` all declare `platforms: [.iOS(.v27), .macOS(.v27)]` at the SPM
package level (`Package.swift` in all four). Any app that links
`foundationmodels_apple` via SPM must have `IPHONEOS_DEPLOYMENT_TARGET >=
27.0` — this is a hard, transitive SPM constraint on the **whole app
binary**, not a per-API runtime check.

Consumer `../chat-on-device` implements an AFM → Gemma → GGUF cascade
(ADR-0009 there) precisely so devices without Apple Intelligence fall back
to a local model. This works correctly on the **hardware** dimension
(ineligible chip → AFM reports `available: false`, cascade proceeds) but
**not** on the **OS-version** dimension: a device below iOS/macOS 27 can't
even install the app, regardless of which backend it would actually use at
runtime — including Gemma, whose own plugin (`flutter_gemma` /
`flutter_gemma.podspec`) only requires **iOS 16.0**.

Full reproduction, evidence and a fix sketch: **FND-0011**
(`.archagents/11-assessment/findings.md`).

## Contexto

Discovered 2026-08-12 while triaging the Gemma-native-engine residual on
the `chat-on-device` consumer (their TCK-0059/TCK-0060). Same shape as
FND-0009/TCK-0042 (consumer-reported iOS build gate) but a different root
cause — that one was a compile error (`SecTask`/`OCRTool` iOS symbols
missing), already closed; this one is a deployment-target propagation
issue and the app still can't even reach the compile step on affected
devices.

## Evidência

- `packages/foundationmodels_apple/ios/foundationmodels_apple/Package.swift:51-53`
- `packages/foundationmodels_apple/macos/foundationmodels_apple/Package.swift:54-56`
- `third_party/foundationmodels-swift/Package.swift:16-18`
- `third_party/foundationmodels-swift/ios-bridge/Package.swift:7-10`
- `third_party/foundationmodels-swift/FoundationModelsCore/Package.swift:28-31`
  (weak-link `FoundationModels` exists, but **macOS-only**, and for an
  unrelated reason — TCK-0150, Xcode-beta SDK mismatch, not OS-version
  fallback)
- No `@available(iOS 27, *)` guards found anywhere under
  `packages/foundationmodels_apple` (grepped, zero matches)
- Consumer repro: `flutter run` on a physical iPhone 14 (`iPhone14,7`, iOS
  26.5.2 — permanently AFM-ineligible hardware, the ideal fallback-test
  device) fails before compiling: `iOS 26.5.2 doesn't match Runner.app's
  iOS 27.0 deployment target`

## Impacto observado ou esperado

Any consumer wanting "AFM when available, universal local fallback
otherwise" is capped to the AFM OS floor for the **entire** app, on
**every** device — including the exact devices that would only ever use
the fallback. This narrows the real-world reach of the fallback pattern to
devices that would mostly already have AFM anyway.

## Perguntas em aberto

- Real minimum iOS/macOS needed by `FoundationModelsCore`'s **non-AFM**
  code paths (MLX / CoreAI targets) — is iOS 16/macOS 13 actually
  sufficient, or do other dependencies (mlx-swift-lm, swift-transformers)
  impose their own higher floor?
- Scope of `@available` retrofitting — how many call sites in
  `FoundationModelsCore.swift` directly reference `FoundationModels`
  framework symbols outside the already-macOS-guarded PCC/Vision paths?
- Whether lowering the floor is worth doing before or after pub.dev
  publish (TCK-0041/TCK-0052 already shipped `v1.0.4`) — this would be a
  breaking-ish platform-support change for existing consumers pinned to
  `from: "1.0.4"`.

## Seções de Docs relevantes

- `packages/foundationmodels_apple/README.md` §Requirements
- `CONTINUATION.md` (upstream Core is single source of truth, ADR-0002)

## Fora de escopo (por ora)

- Marking iOS FM generation `supported` on ineligible hardware (unrelated —
  already correctly gated, see TCK-0035)
- Any change to `chat-on-device` itself (that consumer's
  `IPHONEOS_DEPLOYMENT_TARGET=27.0` is *correct* given today's floor here —
  nothing to fix on their side until this ticket resolves)

## Log de transições

- `2026-08-12T10:00:00-03:00` — **raw** — criado via Intake
  (`source: consumer-chat-on-device-report`), a partir de FND-0011, achado
  durante sessão no consumer `chat-on-device`. Avaliação/priorização
  deferida — não é regressão nem bloqueia nada hoje.
