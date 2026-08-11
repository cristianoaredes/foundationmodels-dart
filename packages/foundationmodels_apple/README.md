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
(pinned, semver-tagged). For local development against a monorepo checkout, set
the environment variable **before** resolving packages (the manifest reads it):

```sh
# Preferred local layout: distribution-mirror tree (CoreAI sources excluded).
export FOUNDATIONMODELS_SWIFT_PATH=/path/to/foundationmodels-swift
# Monorepo tip (full CoreAI): point at foundationmodels-js/swift ONLY if CoreAI
# package deps resolve; otherwise SPM fails with CoreAILanguageModels missing
# (FND-0010). Mirror layout is the safe default for iOS consumers.
# then: flutter build ios / flutter build macos (or xcodebuild / swift build)
```

**Layout contract (TCK-0042 / FND-0010):**

| Path shape | Products | Use when |
|------------|----------|----------|
| GitHub mirror `from: "1.0.3"`+ / local mirror clone | Core + ios-bridge (CoreAI stubbed/excluded) | Consumers, CI, iOS sim |
| Monorepo `foundationmodels-js/swift` | Core + ios-bridge + CoreAI deps | Local Apple full tip on Mac |

Do **not** point `FOUNDATIONMODELS_SWIFT_PATH` at monorepo Core alone without the monorepo Package graph.

Default pin until TCK-0044: `from: "1.0.3"`. After publish: `from: "1.0.3"` (duplex + iOS guards).

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
