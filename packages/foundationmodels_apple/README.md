# foundationmodels_apple

Apple platform implementation (iOS + macOS) of the `foundationmodels` federated
plugin. This package is a thin bridge between Flutter platform channels and the
shared Swift core from the upstream
[foundationmodels-js](https://github.com/cristianoaredes/foundationmodels-js)
monorepo (`FoundationModelsCore` + `FoundationModelsIOSBridge`), which wraps the
Apple Foundation Models framework.

> **Status:** host-native + Flutter live macOS measured (closeout 2026-08-11).
> iOS **Simulator compile** requires Core guards (TCK-0042); on-device FM
> generation remains separate evidence (not simulator-only).

## Architecture

One MethodChannel, one EventChannel (ADR-0001 §6/§7):

| Channel | Purpose |
|---|---|
| `foundationmodels/rpc` | Single `invoke` operation whose argument is a daemon-shaped envelope `{"id": "rpc_...", "method": "foundationmodels.<op>", "params": {...}}`. Unary success returns the bare JSON-RPC `result`; failure is a `FlutterError(code: "<jsonRpcCode>", message: ..., details: errorData)` where `errorData.code` is the stable machine code (e.g. `CONTEXT_OVERFLOW`). |
| `foundationmodels/streams` | Global stream of daemon-shaped events (`run_started`, `text_delta`, `structured_delta`, `tool_call_*`, `message_end`, `done`, `error`), multiplexed by `requestId`. Cancelling the subscription implicitly cancels active native generations (client-EOF analogue). |

The Swift plugin (`FoundationModelsPlugin.swift`, ~330 lines) only translates
channel ↔ dictionary. **No model logic is reimplemented here** — the Swift core
is the single source of truth (non-negotiable, ADR-0001 §9).

## Requirements

| | |
|---|---|
| Xcode | 27+ (SDK 27) |
| iOS | 27+, Apple Intelligence enabled, eligible device (Apple Silicon-class NPU) |
| macOS | 27+, Apple Silicon |
| Flutter | stable with SPM plugin support (≥ 3.27) |
| Dart | ≥ 3.12 |

Always call `availability()` / `capabilities()` first and degrade by
`reasonCode` — simulators have partial coverage, and Apple Intelligence must be
enabled on the device.

## Swift package resolution

The plugin consumes the Swift core as SPM products (`FoundationModelsCore`,
`FoundationModelsIOSBridge`) from the distribution mirror
[`foundationmodels-swift`](https://github.com/cristianoaredes/foundationmodels-swift)
(pinned, semver-tagged). Optional local override via **`FOUNDATIONMODELS_SWIFT_PATH`**
(read by `ios/` and `macos/` `Package.swift` **before** package resolve).

### Path contract (TCK-0047 / FND-0010) — decision table

| Intent | Set `FOUNDATIONMODELS_SWIFT_PATH`? | Path must be | CoreAI | Use when |
|--------|-------------------------------------|--------------|--------|----------|
| **CI / consumers / iOS sim (default)** | **unset** | n/a — GitHub `from: "1.0.4"` | stub / excluded | Always safe |
| **Local mirror clone** | **set** | root of [foundationmodels-swift](https://github.com/cristianoaredes/foundationmodels-swift) layout (`…/FoundationModelsCore` + `…/ios-bridge` present; CoreAI excluded) | stub / excluded | Offline pin / patch mirror |
| **Full Apple tip on Mac** | **set** | monorepo `foundationmodels-js/swift` (same subdirs + CoreAI package graph resolves) | full deps | Local CoreAI/MLX tip only |
| **Forbidden** | set | monorepo **Core alone**, random subfolder, or path without both `FoundationModelsCore` and `ios-bridge` | **breaks** | — |

When the env var is set, manifests resolve:

```text
$FOUNDATIONMODELS_SWIFT_PATH/FoundationModelsCore
$FOUNDATIONMODELS_SWIFT_PATH/ios-bridge
```

**Recovery if SPM fails with `CoreAILanguageModels` / missing module:**

1. `unset FOUNDATIONMODELS_SWIFT_PATH` and rebuild (uses mirror `from: "1.0.4"`), **or**
2. Point the env at a **full** monorepo `swift/` tree where CoreAI deps resolve, **or**
3. Point at a **mirror-layout** clone (CoreAI sources excluded by design).

```sh
# Default (recommended for consumers / iOS sim): leave unset
unset FOUNDATIONMODELS_SWIFT_PATH

# Optional local mirror layout:
# export FOUNDATIONMODELS_SWIFT_PATH=/path/to/foundationmodels-swift

# Optional monorepo full tip (Mac only; CoreAI deps must resolve):
# export FOUNDATIONMODELS_SWIFT_PATH=/path/to/foundationmodels-js/swift

flutter build ios   # or macos / xcodebuild
```

Default pin: `from: "1.0.4"` (duplex + iOS guards; Package.swift iOS/macOS).

## Layout decision: `ios/` + `macos/` (not shared `darwin/`)

SwiftPM requires a target's sources to live **inside** the package directory, so
the macOS package cannot point `path:` at `../../ios/...`. The thin plugin
source file is therefore **duplicated**:

- `ios/foundationmodels_apple/Sources/foundationmodels_apple/FoundationModelsPlugin.swift`
- `macos/foundationmodels_apple/Sources/foundationmodels_apple/FoundationModelsPlugin.swift`

Keep both copies byte-identical (`diff` them after any edit). The duplication is
acceptable because the file is a pure channel↔bridge translator — all logic
changes happen upstream in `FoundationModelsCore`, not here. The shared
`darwin/` directory convention was considered and rejected: a single
`Package.swift` would serve both platforms, but per-platform manifests make the
iOS/macOS deployment targets explicit and match Flutter's per-platform SPM
lookup without relying on fallback search order.

## Upstream extensions required (ADR-0001 §9)

| Marker | Bridge API this plugin calls | Status upstream |
|---|---|---|
| — | `health()`, `availability()`, `capabilities()`, `createSession(config:)`, `disposeSession(sessionId:)`, `respond(params:)` | exists today |
| `U1` | `respondStream(params:onEvent:)` | **implemented** (host + Flutter live) |
| `U2` | `countTokens(params:)` | **implemented** |
| `U3` | `visionOcr` / `visionBarcode` | **implemented** (macOS native tools; iOS fail-closed compile path TCK-0042) |
| `U4` | `logFeedbackAttachment(params:)` | **implemented** |
| `U5` | `transitionSession` / `prewarm` / history | **implemented** |
| `U6` | `cancelGeneration(generationId:)` | **implemented** |
| `U7` | `submitToolResult(params:)` | **implemented** (duplex registry + fail-closed) |

## License

AGPL-3.0-only (with the upstream network clause posture). See the repository
root `LICENSE`. Apple, Apple Intelligence, and Foundation Models are trademarks
of Apple Inc.; this project is not affiliated with or endorsed by Apple Inc.
