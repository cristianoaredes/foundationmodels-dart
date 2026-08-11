---
id: TCK-0048
slug: chat-on-device-runner-lipo
title: "chat-on-device — fix Runner Flutter.framework lipo / full iOS sim build"
source: next-wave-intake
created_at: 2026-08-11T21:00:00-03:00
status: todo
priority: high
category: bug
effort: M
related: [TCK-0046, TCK-0040, TCK-0042]
program: NEXT-WAVE
order: 2
wave: A
executable_now: true
consumer: ../chat-on-device
external_repo: chat-on-device
---

# TCK-0048 — chat-on-device Runner lipo residual

## Gap

TCK-0040/0042 unblocked **package** Core for iPhoneSimulator. Full **chat-on-device** `flutter build ios --simulator` still failed on **Flutter.framework lipo arch check** (tooling), not SecTask. Consumer cannot complete end-to-end sim smoke.

## Ownership

| Layer | Repo | This ticket expects |
|-------|------|---------------------|
| Runner / Pods / Flutter.framework | **chat-on-device** | Fix or document |
| foundationmodels_apple Core | this monorepo | Regress only if package is root cause |

## Depends on

- TCK-0042 **done** (package Core guards)  
- Sibling checkout at `../chat-on-device` recommended  

## Work

1. Reproduce on Mac:
   ```bash
   cd ../chat-on-device
   flutter clean && flutter pub get
   flutter build ios --simulator 2>&1 | tee /tmp/chat-ios-sim.log
   ```
2. Classify error:
   - **A** Flutter.framework / lipo / arch → consumer tooling (DerivedData, `flutter precache`, Xcode 27 beta quirk)
   - **B** SecTask / OCRTool / CoreAI → package regression → fix here + reopen FND-0009 class
   - **C** path dep / Package.resolved → pin docs
3. Fix in the owning repo; capture log under this run’s evidence (or consumer `.archagents`).
4. Smoke: mock path (`USE_MOCK_LLM=true` if applicable) + optional Apple path.
5. Update consumer pin/docs if foundationmodels SHA/path changed.
6. Sync `FOUNDATIONMODELS-DART-GAPS.md` in consumer if still stale.

## AC

- [ ] `flutter build ios --simulator` succeeds for chat-on-device **or** residual is documented with root-cause class A/B/C and owner
- [ ] If A: steps to recover recorded (clean, precache, arch exclude)
- [ ] If B: package patch + tests/evidence in this repo
- [ ] No claim of live FM `supported` without device evidence
- [ ] Cross-link evidence path in RUN report

## Evidence template

```text
SMOKE chat_runner build_ios_sim=ok|fail class=A|B|C
# log: .archagents/13-execution/runs/RUN-*/evidence/chat-ios-sim.log
```

## Files likely to touch

**Consumer:** `ios/`, `pubspec.yaml`, Podfile, docs  
**Package (only if B):** `packages/foundationmodels_apple/**`, mirror Core  

## Out of scope

- PCC (TCK-0028)  
- Publishing pub.dev  

## Risks

Xcode 27 beta SPM/Flutter instability (known intermittent NSMutableArray index bug). Prefer clean rebuild before code changes.
