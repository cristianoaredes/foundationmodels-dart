# foundationmodels-dart

Dart/Flutter adapter for [FoundationModels JS](https://github.com/cristianoaredes/foundationmodels-js) — on-device **Apple Foundation Models** (Apple Intelligence) via the shared Swift core (`FoundationModelsCore` + `FoundationModelsIOSBridge`).

[![License: AGPL-3.0-only](https://img.shields.io/badge/license-AGPL--3.0--only-blue.svg)](LICENSE)
[![Upstream](https://img.shields.io/badge/upstream-foundationmodels--js-black.svg)](https://github.com/cristianoaredes/foundationmodels-js)
[![Dart CI](https://github.com/cristianoaredes/foundationmodels-dart/actions/workflows/dart.yml/badge.svg)](https://github.com/cristianoaredes/foundationmodels-dart/actions/workflows/dart.yml)
[![Mirror SPM](https://img.shields.io/badge/SPM-foundationmodels--swift%201.0.4-informational.svg)](https://github.com/cristianoaredes/foundationmodels-swift)
[![Status](https://img.shields.io/badge/status-v1%20shippable%20(git--only)-brightgreen.svg)](#status-snapshot)

The Swift core is the **single source of truth**. This repo adds:

1. Idiomatic **Dart API** + deterministic **mock** (CI / no Mac)  
2. **Flutter plugin** (iOS + macOS) over platform channels  
3. Ecosystem packages: tools, agent, daemon client, MCP server, RAG, eval, policy, OpenAI-shaped server, LangChain adapter  

No model weights and no silent cloud fallback live in Dart.

---

## Table of contents

- [Status snapshot](#status-snapshot)
- [Architecture](#architecture)
- [Packages](#packages)
- [Quick start](#quick-start)
- [Apple / Swift path contract](#apple--swift-path-contract)
- [Tools, agent, and MCP](#tools-agent-and-mcp)
- [Platform requirements](#platform-requirements)
- [Developing & validating](#developing--validating)
- [Parity & honesty](#parity--honesty)
- [Distribution](#distribution)
- [Governance & backlog](#governance--backlog)
- [Roadmap (historical vs current)](#roadmap-historical-vs-current)
- [Invariants](#invariants)
- [License](#license)
- [Trademarks](#trademarks)
- [Author](#author)

---

## Status snapshot

| Area | Status |
|------|--------|
| Public API (`foundationmodels`) | ✅ Done — mock + transport; tests green |
| Platform interface | ✅ RPC v2, stream events, typed errors |
| Apple plugin | ✅ Live macOS E2E + host-native smokes measured |
| Tools duplex | ✅ **supported** (host + Flutter live dual-run) |
| Agent kit | ✅ `FmAgent` tool loop + HITL + AG-UI-shaped events |
| MCP server + client | ✅ `foundationmodels_mcp` — stdio server, client, SSE, live env harness |
| Daemon client | ✅ Fake-peer E2E; live binary often env-limited (dyld/CoreAI) |
| SPM mirror | ✅ [foundationmodels-swift](https://github.com/cristianoaredes/foundationmodels-swift) **`from: "1.0.4"`** |
| pub.dev | ⏸ Git-only — **ADR-0002** stay-private (`publish_to: none`) |
| CoreAI content | ⏸ Fail-closed / not measured without registered model |
| MLX content | ⛔ Blocked — needs weights (**TCK-0049**) |
| PCC | ⛔ Blocked — Apple entitlement (**TCK-0028**) |
| Open `todo` | **None** — L3 executable work exhausted |

**Handoff:** [`CONTINUATION.md`](CONTINUATION.md) · **Status narrative:** [`docs/PROJECT-STATUS.md`](docs/PROJECT-STATUS.md) · **Delivery log:** [`docs/DELIVERY-LOG.md`](docs/DELIVERY-LOG.md) · **Parity:** [`docs/parity.md`](docs/parity.md) · **Ops:** [`.archagents/15-backlog/OPEN-BACKLOG.md`](.archagents/15-backlog/OPEN-BACKLOG.md) · **Agents:** [`AGENTS.md`](AGENTS.md)

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│ Apps (e.g. chat-on-device)                                        │
│  foundationmodels  +  optional agent / tools / mcp / apple       │
└───────────────────────────────┬──────────────────────────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        ▼                       ▼                       ▼
┌───────────────────┐  ┌───────────────────┐  ┌───────────────────┐
│ foundationmodels  │  │ foundationmodels_ │  │ foundationmodels_ │
│ (public API)      │  │ agent / tools /   │  │ mcp (stdio MCP    │
│ mock · sessions · │  │ daemon · server · │  │  server subset)   │
│ tools duplex ·    │  │ rag · eval · …    │  │                   │
│ stream · cancel   │  │                   │  │                   │
└─────────┬─────────┘  └───────────────────┘  └───────────────────┘
          │ implements
┌─────────▼─────────┐
│ platform_interface│  invoke(envelope) · streamEvents · typed errors
└─────────┬─────────┘
          │ MethodChannel foundationmodels/rpc
          │ EventChannel  foundationmodels/streams
┌─────────▼─────────┐
│ foundationmodels_ │  Thin plugin → FoundationModelsBridge
│ apple (iOS/macOS) │
└─────────┬─────────┘
          │ SPM: foundationmodels-swift 1.0.4  OR  FOUNDATIONMODELS_SWIFT_PATH
┌─────────▼─────────┐
│ Core + ios-bridge │  Shared Swift (upstream monorepo / mirror)
└─────────┬─────────┘
          ▼
   Apple Foundation Models (on-device)
```

**Alternate transport (no Flutter):** `foundationmodels_daemon` → Unix-socket JSON-RPC → macOS `foundationmodels-daemon` binary (when the host binary runs; often blocked by OS/CoreAI dyld skew — client path is still tested via fake peer).

---

## Packages

Pub **workspace** (Dart 3.12+). Resolve from the **repository root**.

### Core (public app surface)

| Package | Role |
|---------|------|
| [`foundationmodels`](packages/foundationmodels) | Public Dart API: `respond`, `stream`, sessions, `FmSchema`, tools, mock, cancel |
| [`foundationmodels_platform_interface`](packages/foundationmodels_platform_interface) | Transport contract, events, errors (pure Dart) |
| [`foundationmodels_apple`](packages/foundationmodels_apple) | Flutter plugin iOS + macOS → Swift core |

### Tools & agent

| Package | Role |
|---------|------|
| [`foundationmodels_tools`](packages/foundationmodels_tools) | `FmToolRouter` — duplex `tool_call_*` → `submitToolResult` |
| [`foundationmodels_agent`](packages/foundationmodels_agent) | `FmAgent` — tool loop, HITL interrupts, AG-UI-shaped events, intent router |
| [`foundationmodels_mcp`](packages/foundationmodels_mcp) | **MCP server** (stdio) + **client** + SSE transport + env-gated live test |

### Transport & ecosystem

| Package | Role |
|---------|------|
| [`foundationmodels_daemon`](packages/foundationmodels_daemon) | Unix-socket client for macOS daemon |
| [`foundationmodels_policy`](packages/foundationmodels_policy) | Optional PII redaction |
| [`foundationmodels_rag`](packages/foundationmodels_rag) | Local semantic index (pure Dart) |
| [`foundationmodels_eval`](packages/foundationmodels_eval) | Eval harness + traces |
| [`foundationmodels_server`](packages/foundationmodels_server) | OpenAI-compatible HTTP (`shelf`) |
| [`foundationmodels_langchain`](packages/foundationmodels_langchain) | LangChain.dart-oriented adapter |

All packages: **`publish_to: none`** (git consumption). License monorepo: **AGPL-3.0-only**.

---

## Quick start

### Mock (any machine, CI)

```dart
import 'package:foundationmodels/foundationmodels.dart';

final fm = await createFoundationModels(); // no Apple provider → mock

final r = await fm.respond(
  input: 'Hello',
  instructions: 'Be brief.', // trusted channel — never paste raw user/tool text here
);
print(r.text);

final session = await fm.createSession(instructions: 'Answer concisely.');
await for (final event in session.stream(input: 'One sentence on on-device AI.')) {
  // TextDelta, tool events, terminal errors…
}
await session.dispose();
```

### Flutter + Apple plugin

1. Depend on `foundationmodels` + `foundationmodels_apple` (path or git).  
2. Ensure iOS/macOS targets match [platform requirements](#platform-requirements).  
3. Leave `FOUNDATIONMODELS_SWIFT_PATH` **unset** for published mirror **1.0.4** (default).  
4. Call `availability()` / `capabilities()` before advanced features.

Minimal host: [`example/`](example/).

### MCP server (stdio)

```dart
import 'dart:io';
import 'package:foundationmodels/foundationmodels.dart';
import 'package:foundationmodels_mcp/foundationmodels_mcp.dart';

final fm = await createFoundationModels();
final mcp = FmMcpServer(fm: fm);
await mcp.serve(input: stdin, output: stdout.add);
```

See [`packages/foundationmodels_mcp/README.md`](packages/foundationmodels_mcp/README.md) and [DES-0004](.archagents/16-designs/DES-0004-mcp-package.md).

---

## Apple / Swift path contract

Full table: [`packages/foundationmodels_apple/README.md`](packages/foundationmodels_apple/README.md) (TCK-0047 / FND-0010).

| Intent | `FOUNDATIONMODELS_SWIFT_PATH` | Result |
|--------|-------------------------------|--------|
| **CI / consumers / iOS sim (default)** | **unset** | GitHub SPM `from: "1.0.4"` (CoreAI stub/excluded) |
| Local mirror clone | set → mirror layout root | Same products as published mirror |
| Full monorepo tip (Mac) | set → `foundationmodels-js/swift` | Core + ios-bridge + CoreAI **if** deps resolve |
| **Forbidden** | monorepo Core alone | SPM fails (e.g. missing `CoreAILanguageModels`) |

```sh
# Recommended for apps:
unset FOUNDATIONMODELS_SWIFT_PATH

# Optional full tip:
# export FOUNDATIONMODELS_SWIFT_PATH=/path/to/foundationmodels-js/swift
```

---

## Tools, agent, and MCP

### Tools (duplex)

- Define `FmTool.static` / `.callback` / `.native` on `stream(...)`.  
- Runtime can auto-execute (`autoExecuteTools: true`) or leave execution to a host/agent (`false`).  
- Parity: **tools duplex = supported** (measured).  

### Agent (`foundationmodels_agent`)

```dart
final agent = FmAgent(fm: fm, tools: [myCallbackTool], requireHitl: false);
await for (final e in agent.run(input: '…')) {
  // FmAgentRunStarted, tool events, text, RunFinished / RunError
}
```

- Always uses `autoExecuteTools: false` (single-executor: agent owns `tools.result`).  
- Optional HITL: interrupt → approve/edit/reject.  
- Events are **AG-UI-shaped**, not MCP.

### MCP (`foundationmodels_mcp`)

| Piece | Spec | Notes |
|-------|------|--------|
| Server | DES-0004 | stdio NDJSON: `initialize`, `tools/list`, `tools/call`, `fm_respond` |
| Client | DES-0005 | `FmMcpClient` + loopback / SSE; tools → `FmTool.callback` |
| Live | TCK-0059 | `FM_MCP_SSE_URL` or `UAB_MCP_URL` (optional `FM_MCP_BEARER`) |

Does **not** replace `FmAgent`. Does **not** claim Apple matrix cells.  
Package README: [`packages/foundationmodels_mcp/README.md`](packages/foundationmodels_mcp/README.md).

---

## Platform requirements

| | Requirement |
|--|-------------|
| iOS | 27+, Apple Intelligence where applicable, eligible device |
| macOS | 27+, Apple Silicon preferred |
| Toolchain | Xcode 27 / SDK 27, Flutter ≥ 3.27 (SPM plugins), Dart ≥ 3.12 |
| Non-Apple OS | Mock / pure-Dart packages only |

Always gate on `availability()` / `capabilities()` and typed `error.data.code`.

---

## Developing & validating

```sh
cd foundationmodels-dart
dart pub get   # workspace root — required

# Core
(cd packages/foundationmodels_platform_interface && dart test && dart analyze --fatal-infos)
(cd packages/foundationmodels && dart test && dart analyze --fatal-infos)
(cd packages/foundationmodels_apple && flutter analyze --fatal-infos)

# Agent / tools / MCP / daemon
(cd packages/foundationmodels_agent && dart test)
(cd packages/foundationmodels_mcp && dart test)
(cd packages/foundationmodels_daemon && dart test)
(cd packages/foundationmodels && dart test test/tools_e2e_test.dart)
```

Analyzer bar: **`--fatal-infos`** (and warnings where enforced).

CI: [`.github/workflows/dart.yml`](.github/workflows/dart.yml) · optional Apple workflow docs under `docs/ci/`.

---

## Parity & honesty

Capability status is maintained in **[`docs/parity.md`](docs/parity.md)**.

Rules:

1. Never mark a cell **`supported`** without measured evidence (or honest pure-Dart “measured” for offline packages).  
2. Fail-closed for missing models / entitlements — **no silent remap** to `apple.system`.  
3. Protocol mapping: [`docs/protocol-mapping.md`](docs/protocol-mapping.md).  
4. Upstream extension specs: [`docs/specs/`](docs/specs/).

---

## Distribution

| Artifact | How |
|----------|-----|
| This monorepo | **Git** (path or git dependency) |
| Swift core for SPM apps | [foundationmodels-swift](https://github.com/cristianoaredes/foundationmodels-swift) tag **≥ 1.0.4** |
| pub.dev | **Not published** — [ADR-0002](.archagents/09-decisions/ADR-0002-stay-private-git-only.md); prep checklist under `.archagents/15-backlog/PUBLISH-CHECKLIST.md` |

Real `dart pub publish` requires human SAFETY approval.

---

## Governance & backlog

Operated with **codebase-ops** (tickets, runs, verify, ADRs).

| Resource | Path |
|----------|------|
| Agent contract | [`AGENTS.md`](AGENTS.md) |
| Session handoff | [`CONTINUATION.md`](CONTINUATION.md) |
| Project status (full) | [`docs/PROJECT-STATUS.md`](docs/PROJECT-STATUS.md) |
| Delivery log (PRs/runs) | [`docs/DELIVERY-LOG.md`](docs/DELIVERY-LOG.md) |
| Plan board | [`.archagents/12-inception/plan-board.md`](.archagents/12-inception/plan-board.md) |
| Open backlog SoT | [`.archagents/15-backlog/OPEN-BACKLOG.md`](.archagents/15-backlog/OPEN-BACKLOG.md) |
| CSV + tickets | [`.archagents/15-backlog/`](.archagents/15-backlog/) |
| Handoff snapshot | `.archagents/13-execution/snapshots/TCK-0049-20260811-232337/` |

**Open:** TCK-0049 (MLX) · TCK-0028 (PCC) — both **blocked**. Zero `todo`.

---

## Roadmap (historical vs current)

Original phase plan (ADR-0001) is largely **implemented** in-repo:

| Phase | Content | State |
|------:|---------|--------|
| 0–2 | Spike → streaming + cancel | ✅ Measured |
| 3 | Full surface (sessions, guided, vision, …) | ✅ Honest parity |
| 4 | Tools duplex | ✅ Supported |
| 5 | RAG + daemon client | ✅ Packages present |
| 6 | Eval + traces | ✅ Package present |
| 7 | Agent + MLX/CoreAI exposure | ✅ Agent; MLX/CoreAI **fail-closed / Stage 2** |
| 8 | Server + LangChain adapter | ✅ Packages present |
| + | MCP server + client + SSE | ✅ Stage 1–2 (`foundationmodels_mcp`) |

Remaining gates (this repo): **MLX weights (TCK-0049)**, **PCC entitlement (TCK-0028)**, optional **pub.dev** (human), optional **live daemon** when OS/CoreAI dyld allows.

---

## Invariants

1. **No silent cloud fallback.** No provider → mock.  
2. **Typed errors** via `error.data.code` — never fake success.  
3. **`instructions` is trusted** — never paste untrusted user/tool/web/MCP content into it.  
4. **Fail-closed image allowlist.**  
5. **Parity honesty** — `supported` only with evidence.  
6. **Only streaming** is truly interruptible for generation cancel.  

---

## License

**AGPL-3.0-only**, consistent with the upstream monorepo. See [LICENSE](LICENSE) and [NOTICE](NOTICE) (network clause, AGPL §13).

---

## Trademarks

Apple, Apple Intelligence, Foundation Models, iOS, macOS, Xcode, and Swift are trademarks of Apple Inc., registered in the U.S. and other countries and regions. This is an independent open-source project and is **not affiliated with, sponsored by, or endorsed by Apple Inc.**

---

## Author

**Cristiano Aredes** — [github.com/cristianoaredes](https://github.com/cristianoaredes)
