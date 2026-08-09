# foundationmodels_apple

Apple platform implementation (iOS + macOS) of the `foundationmodels` federated
plugin. This package is a thin bridge between Flutter platform channels and the
shared Swift core from the upstream
[foundationmodels-js](https://github.com/cristianoaredes/foundationmodels-js)
monorepo (`FoundationModelsCore` + `FoundationModelsIOSBridge`), which wraps the
Apple Foundation Models framework.

> **Status: phase 0 (spike).** The Swift and Dart code in this package has been
> statically reviewed but **not yet compiled or tested on CI/device**. Several
> entry points call the *target* ios-bridge API that still needs to be
> implemented upstream — every such call site is marked with an
> `UPSTREAM(U1)..(U7)` comment mapping to ADR-0001 §9. See the repository
> README for the phase roadmap.

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
export FOUNDATIONMODELS_SWIFT_PATH=/path/to/foundationmodels-swift
# then: flutter build ios / flutter build macos (or xcodebuild / swift build)
```

This mirrors the `FOUNDATIONMODELS_CORE_PATH` / `FOUNDATIONMODELS_IOS_BRIDGE_PATH`
overrides already used by the React Native adapter upstream.

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
| `U1` | `respondStream(params:onEvent:)` | core ready (`StreamingDelta`), bridge surface pending |
| `U2` | `countTokens(params:)` | core ready (`tokenCount(for:)`), bridge surface pending |
| `U3` | `visionOcr(params:)`, `visionBarcode(params:)` | core ready (`VisionHandler`), bridge surface pending |
| `U4` | `logFeedbackAttachment(params:)` | daemon handler ready, bridge surface pending |
| `U5` | `transitionSession(params:)`, `prewarm(params:)`, `createSession` with `history` | core ready (`SessionRegistry`), bridge surface pending |
| `U6` | `cancelGeneration(generationId:)` | cooperative cancel ready in daemon, bridge surface pending |
| `U7` | `submitToolResult(params:)` | duplex tool bridge (phase 4), bridge surface pending |

Until these land, the package compiles only against a bridge that has the U1–U7
surface; the method routing and wire contract above are the contract-target the
upstream tickets will implement.

## License

AGPL-3.0-only (with the upstream network clause posture). See the repository
root `LICENSE`. Apple, Apple Intelligence, and Foundation Models are trademarks
of Apple Inc.; this project is not affiliated with or endorsed by Apple Inc.
