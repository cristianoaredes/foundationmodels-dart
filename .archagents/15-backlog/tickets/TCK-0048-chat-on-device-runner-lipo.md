---
id: TCK-0048
slug: chat-on-device-runner-lipo
title: "chat-on-device — fix Runner Flutter.framework lipo / full iOS sim build"
source: next-wave-intake
created_at: 2026-08-11T21:00:00-03:00
status: done
priority: high
category: bug
effort: M
related: [TCK-0046, TCK-0040, TCK-0042]
program: NEXT-WAVE
order: 2
wave: A
consumer: ../chat-on-device
done_at: 2026-08-11T22:00:00-03:00
run: RUN-20260811-wave-a
---

# TCK-0048 — chat-on-device Runner lipo residual

## Closure (2026-08-11)

**done** — class **A** (Flutter tooling + Xcode 27 lipo).

### Root cause

`lipo -verify_arch arm64 x86_64` on Xcode 27 fails multi-arch (`requires exactly one input file`) even when the fat binary lists both arches. Flutter 3.44 `thinFramework` aborts → status 255.

### Fix (consumer `chat-on-device`)

- `ios/Flutter/Debug.xcconfig` + `Release.xcconfig`: `ARCHS=arm64`, exclude x86_64 sim  
- `project.pbxproj` + Podfile `post_install`: same  

### Evidence

```text
✓ Built build/ios/iphonesimulator/Runner.app
SMOKE chat_runner build_ios_sim=ok class=A
```

Log: `RUN-20260811-wave-a/evidence/chat-ios-sim.log`  
Note: `evidence/chat-runner-lipo-fix.md`

## AC

- [x] `flutter build ios --simulator` succeeds
- [x] Class A documented with recovery
- [x] Package Core not root cause (no SecTask regression)
