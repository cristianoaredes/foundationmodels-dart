# foundationmodels-dart

On-device AI primitives for Dart & Flutter — a Dart/Flutter adapter for
[FoundationModels JS](https://github.com/cristianoaredes/foundationmodels-js),
bridging to the **Apple Foundation Models** framework through the shared Swift
core (`FoundationModelsCore` + `FoundationModelsIOSBridge`).

[![License: AGPL-3.0-only](https://img.shields.io/badge/license-AGPL--3.0--only-blue.svg)](LICENSE)
[![Upstream](https://img.shields.io/badge/upstream-foundationmodels--js-black.svg)](https://github.com/cristianoaredes/foundationmodels-js)
[![Dart CI](https://github.com/cristianoaredes/foundationmodels-dart/actions/workflows/dart.yml/badge.svg)](https://github.com/cristianoaredes/foundationmodels-dart/actions/workflows/dart.yml)
[![Status: phase 0](https://img.shields.io/badge/status-phase%200%20(spike)-orange.svg)](#roadmap)

The Swift core stays the single source of truth (upstream ADR-0002): this
repository adds only transport (platform channels carrying the daemon's
JSON-RPC-shaped envelopes) and an idiomatic Dart API. No model logic is
reimplemented in Dart or in the plugin.

## Architecture

```
┌────────────────────────────┐
│ package:foundationmodels   │  Public Dart API + deterministic mock provider
│  classify / extract / rank │  (no Flutter dependency — testable in a plain VM)
│  summarize / respond /     │
│  stream / sessions         │
└─────────────┬──────────────┘
              │ implements
┌─────────────▼──────────────┐
│ foundationmodels_platform_ │  Transport contract: invoke(envelope),
│ interface                  │  global streamEvents, typed errors, FmMethods
└─────────────┬──────────────┘
              │ MethodChannel "foundationmodels/rpc"   (daemon-shaped envelopes)
              │ EventChannel  "foundationmodels/streams" (events by requestId)
┌─────────────▼──────────────┐
│ foundationmodels_apple     │  Thin plugin: envelope router →
│  (iOS + macOS, SPM)        │  FoundationModelsBridge.shared
└─────────────┬──────────────┘
              │ in-process [String: Any] ("daemon-shaped params")
┌─────────────▼──────────────┐
│ FoundationModelsCore +     │  Shared Swift core (upstream monorepo /
│ FoundationModelsIOSBridge  │  foundationmodels-swift mirror)
└─────────────┬──────────────┘
              ▼
     Apple Foundation Models (on-device, iOS 27+ / macOS 27+)
```

## Packages

| Package | Role | Status |
|---|---|---|
| [`foundationmodels`](packages/foundationmodels) | Public Dart API, typed errors, `FmSchema`, deterministic mock provider | phase 0 — in development |
| [`foundationmodels_platform_interface`](packages/foundationmodels_platform_interface) | Transport contract, stream event types, error mapping | phase 0 — in development |
| [`foundationmodels_apple`](packages/foundationmodels_apple) | iOS + macOS plugin over the Swift core | phase 0 — written, **not compiled/tested yet** (see its README) |

## Quick start

```dart
import 'package:foundationmodels/foundationmodels.dart';

// No provider → deterministic mock (works everywhere, no Apple hardware).
final fm = await createFoundationModels();

// On iOS/macOS with foundationmodels_apple registered:
// final fm = await createFoundationModels(
//   providers: [AppleFoundationModelsProvider()],
// );

final cls = await fm.classify(
  input: 'I love this product!',
  labels: ['positive', 'negative'],
);

final session = await fm.createSession(instructions: 'Answer concisely.');
await for (final event in session.stream(input: 'One sentence on on-device AI.')) {
  if (event is TextDelta) stdout.write(event.delta);
}
await session.dispose();
```

## Platform requirements

| | |
|---|---|
| iOS | 27+, Apple Intelligence enabled, eligible device (Apple Silicon-class NPU) |
| macOS | 27+, Apple Silicon |
| Toolchain | Xcode 27 / SDK 27, Flutter ≥ 3.27 (SPM plugin support), Dart ≥ 3.12 |

Call `availability()` / `capabilities()` before using streaming, guided
generation, multimodal, native tools, vision, or feedback — degrade by the
stable `reasonCode`. Android/Windows/Linux: contract parity via the mock
provider only — the Apple Foundation Models framework does not exist outside
Apple platforms.

## Developing in this repository

This repo uses a [pub workspace](https://dart.dev/tools/pub/workspaces)
(Dart 3.12+). From the repository root:

```sh
dart pub get            # resolves all three packages at once (shared lockfile at root)
dart test -C packages/foundationmodels_platform_interface
dart test -C packages/foundationmodels
dart analyze            # from any package directory (or the root, covering the workspace)
```

Note for contributors: each package's `pubspec.yaml` declares
`resolution: workspace` — always resolve from the repository root, not from
individual package directories.

For native development, point the plugin at a local Swift core checkout:
`export FOUNDATIONMODELS_SWIFT_PATH=/path/to/foundationmodels-swift`
(see [packages/foundationmodels_apple/README.md](packages/foundationmodels_apple/README.md)).

## Roadmap (ADR-0001 §16)

| Phase | Content |
|---|---|
| **0 — Spike** | Repo + `foundationmodels_apple` routing `health/availability/respond`; real on-device `respond("Hello")` |
| **1 — Core Dart** | Contracts, typed errors, mock, `FmSchema`, core primitives; CI green without a Mac |
| **2 — Streaming** | U1+U6 upstream; multiplexed EventChannel; `CancelToken` with cooperative cancel |
| **3 — Full surface** | U2–U5; guided generation; multimodal; vision; feedback; `contextPolicy`; policy/redaction |
| **4 — Tools** | U7; duplex tool calling; native tools; tool-schema sanitization |
| **5 — RAG + desktop** | Semantic index (local RAG); daemon client over Unix socket for Flutter desktop macOS |
| **6 — Eval + traces** | Eval harness port; end-to-end trace contract |
| **7 — Agent kit + MLX/CoreAI** | Tool loops, HITL, intent router; U8 exposes `apple.mlx:*` / `apple.coreai:*` |
| **8 — Ecosystem** | OpenAI-compatible server in Dart (`shelf`); Dart LLM-client adapters |

Parity discipline mirrors upstream: no capability is reported as supported
without on-device evidence — see [docs/parity.md](docs/parity.md) and
[docs/protocol-mapping.md](docs/protocol-mapping.md).

## License

**AGPL-3.0-only**, consistent with the upstream monorepo. See [LICENSE](LICENSE)
and [NOTICE](NOTICE) (network clause per AGPL §13).

## Trademarks

Apple, Apple Intelligence, Foundation Models, iOS, macOS, Xcode, and Swift are
trademarks of Apple Inc., registered in the U.S. and other countries and
regions. This is an independent open-source project and is **not affiliated
with, sponsored by, or endorsed by Apple Inc.**

## Author

**Cristiano Aredes** — [github.com/cristianoaredes](https://github.com/cristianoaredes)
