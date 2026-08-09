# CONTINUATION — how to pick up this project from any harness

**Read this first.** This file is the handoff contract for `foundationmodels-dart`. It exists so that any future session — another machine, another agent, another harness — can continue the work **without any prior conversational context**. Everything stated here was true at the commit it was added; verify against `git log` if it drifted.

> **TL;DR reading order:** this file → `docs/specs/adr-0001-flutter-adapter.md` (the design) → `docs/specs/upstream-ios-bridge-extensions.md` (what the Swift side still needs) → the `docs/specs/phase-*.md` for the phase you are implementing → `docs/protocol-mapping.md`.

---

## 1. What this is

Dart/Flutter adapter for [FoundationModels JS](https://github.com/cristianoaredes/foundationmodels-js) — a bridge to **Apple Foundation Models** (on-device LLM, iOS 27+/macOS 27+, Apple Intelligence). The shared Swift core (`swift/FoundationModelsCore` + `swift/ios-bridge` in that monorepo) is the **single source of truth**; this repo is the *third adapter* over it (after the macOS JSON-RPC daemon and the React Native host). License: **AGPL-3.0-only**. Author: Cristiano Aredes.

## 2. Current state (snapshot, 2026-08-09)

| Area | Status | Evidence |
|---|---|---|
| `packages/foundationmodels_platform_interface` | ✅ Done — RPC v2 envelope, 10 sealed stream events, 27 typed exceptions 1:1 with `error.data.code`, models | 53 tests green, `dart analyze` clean |
| `packages/foundationmodels` | ✅ Done — runtime primitives (`classify/extract/rank/summarize/respond/stream`), lazy sessions, `FmSchema` (output fail-fast / tool sanitize), `CancelToken`, `contextPolicy: guard`, deterministic offline mock | 92 tests green, `dart analyze` clean |
| `packages/foundationmodels_apple` | ⚠️ Code complete, **never compiled** — envelope router + EventChannel written against the *target* ios-bridge API (U1–U7 markers). Only `health/availability/capabilities/createSession/disposeSession/respond` exist upstream today | `flutter analyze` clean (Dart side only) |
| CI workflows | ⚠️ **Not in `.github/`** — see §5 | files preserved in `docs/ci/` |
| Phases 2–8 | 📋 Specified, not implemented | `docs/specs/phase-*.md` |
| Upstream U1–U9 | 📋 Specified, not implemented | `docs/specs/upstream-ios-bridge-extensions.md` |

Validated on Linux with Flutter 3.44.9 / Dart 3.12.2. No iOS/macOS build or on-device run has ever happened.

## 3. How to validate (any machine with Flutter)

```bash
git clone https://github.com/cristianoaredes/foundationmodels-dart.git
cd foundationmodels-dart
flutter pub get                     # resolves the pub workspace (REQUIRED: Flutter, not bare dart — the workspace includes the apple plugin)
(cd packages/foundationmodels_platform_interface && dart test && dart analyze)
(cd packages/foundationmodels && dart test && dart analyze)
(cd packages/foundationmodels_apple && flutter analyze)   # Dart side only; Swift needs a Mac
```

Expected: **145 tests green**, zero analyzer issues. If this fails on a clean checkout, something regressed — treat as a blocker before any new work.

## 4. What to work on next (priority order)

1. **Upstream U1 + U6** (`docs/specs/upstream-ios-bridge-extensions.md`) — `respondStream` + in-process cancel in the `foundationmodels-js` monorepo ios-bridge. Requires macOS 27 + Xcode 27 + Apple Silicon. Without this, the plugin only does unary calls.
2. **Phase 2 validation** (`docs/specs/phase-2-streaming.md`) — first on-device streaming smoke; update `docs/parity.md` with measured evidence.
3. Phases 3–8 per their specs. Pure-Dart phases (5 RAG/desktop, 6 eval, 8 server) can proceed on any OS **in parallel** with the Mac-gated work.

Development-time Swift linking: `export FOUNDATIONMODELS_SWIFT_PATH=/path/to/foundationmodels-js/swift` (local monorepo checkout). Distribution uses the `foundationmodels-swift` mirror repo (still to be created — open question in ADR-0001 §18).

## 5. Known blockers and quirks

- **CI workflows are NOT in `.github/workflows/`**: the OAuth token used to publish lacked the `workflow` scope and GitHub rejected those commits. The exact files are preserved in **`docs/ci/`** — move/copy them to `.github/workflows/` on any machine with normal git push rights (or re-push once the token has the scope). `dart.yml` expects `subosito/flutter-action` (workspace resolution needs Flutter); `apple.yml` is a documented `workflow_dispatch` placeholder for a self-hosted Apple Silicon runner.
- **Swift code was never compiled**: `FoundationModelsPlugin.swift` (byte-identical copies under `ios/` and `macos/` — SPM requires sources inside each package dir; keep them in sync with `diff`) targets the ios-bridge API of `docs/specs/upstream-ios-bridge-extensions.md`. Calls marked `// UPSTREAM(Un)` will not compile against today's bridge.
- **`publish_to: none`** is set in `foundationmodels_apple/pubspec.yaml` (path dependency). Replace with hosted versions when publishing to pub.dev (phase 8).
- **Transport registration pattern**: `createFoundationModelsAppleTransport()` factory (no static `.instance` holder — deliberate).
- **Analyzer baseline**: `--fatal-infos --fatal-warnings` is the bar; keep it green.

## 6. Invariants (do not violate — inherited from upstream)

1. **No silent cloud fallback.** No provider configured → mock. Never invent a network backend.
2. **Typed errors, never fake success.** `error.data.code` is the contract; map it or surface `UnknownModelException` with details. Never silently drop schema keywords on the output path (tools path sanitizes — see `FmSchema` modes).
3. **`instructions` is a trusted channel.** Never concatenate user input / tool results / web content into it.
4. **Fail-closed security.** Image paths rejected without `allowedImageRoots`; errors never carry model `rawContent`.
5. **Parity honesty.** `docs/parity.md` only marks a capability `supported` with measured on-device evidence (date + device + smoke). `not measured` is the honest default.
6. **Only streaming is truly interruptible.** Cancelling unary `respond` stops the wait, not the generation — documented behavior, not a bug.

## 7. Upstream references (foundationmodels-js monorepo)

- `docs/protocol.md` — full JSON-RPC contract (methods, events, errors, auth, cancellation).
- `docs/parity.md` — capability matrix + evidence discipline.
- `swift/ios-bridge/.../Bridge.swift` — current in-process surface.
- ADR-0002 (Swift core = single source of truth) · ADR-0009 (separate repos) · ADR-0012 (local-first verification) in `.archagents/09-decisions/`.

## 8. Session log (reverse chronological)

- **2026-08-09** — Initial scaffold landed: 3 packages, 145 tests, plugin code, repo meta. Specs for U1–U9 and phases 2–8 added under `docs/specs/`. Published via GitHub MCP (multiple thematic commits; workflows excluded due to token scope — see §5).
