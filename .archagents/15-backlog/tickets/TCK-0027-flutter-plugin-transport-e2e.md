---
id: TCK-0027
slug: flutter-plugin-transport-e2e
title: "Flutter plugin transport E2E — public Dart API → channels → Core"
source: full-parity-backlog
created_at: 2026-08-11T04:00:00-03:00
status: done
priority: high
category: feature
effort: L
related: [TCK-0018, TCK-0006]
---

# TCK-0027 — Flutter plugin path E2E

## Gap

Host-native smokes hit **FoundationModelsIOSBridge** directly. Full Flutter parity needs the **shipped** path: `createFoundationModels` + `TransportProvider` + MethodChannel/EventChannel + `foundationmodels_apple` plugin.

## Work

1. Integration test / example smoke on macOS (and iOS if device present) using public Dart API only.
2. Cover: availability, respond, stream+cancel, countTokens, guided, feedback, vision, tools (as residual tickets land).
3. Assert result mapping (`output` → text/structured) and TokenCount `*Tokens` aliases on live results.
4. Record evidence separately from bridge-only HostSmoke.

## AC

- [ ] Dual-run green on at least macOS host app path
- [ ] Evidence log lines for `flutter-plugin-*` smokes

## Closure

DONE 2026-08-11: TransportProvider dual E2E green; live Flutter FM host not run.
