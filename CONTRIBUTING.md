# Contributing

Thanks for your interest in `foundationmodels-dart` — the Dart/Flutter adapter
for [FoundationModels JS](https://github.com/cristianoaredes/foundationmodels-js).

## Start here

1. Read [`CONTINUATION.md`](CONTINUATION.md) — project state, invariants, and
   how to validate your checkout.
2. Read [`docs/specs/adr-0001-flutter-adapter.md`](docs/specs/adr-0001-flutter-adapter.md)
   — the design contract (ADR-0001).
3. Pick work from the phase specs in [`docs/specs/`](docs/specs/README.md).

## Ground rules

- **The Swift core is upstream.** Logic changes to inference, sessions, guided
  generation, or error mapping belong in the
  [`foundationmodels-js`](https://github.com/cristianoaredes/foundationmodels-js)
  monorepo (`swift/FoundationModelsCore` / `swift/ios-bridge`), not in this
  adapter. This repo translates channels ↔ dictionaries; it never
  reimplements core semantics (ADR-0002 upstream).
- **Parity honesty.** A capability is only marked `supported` in
  `docs/parity.md` with measured on-device evidence (smoke + date + device).
  `not measured` is the honest default.
- **No silent fallbacks.** No hidden cloud backends, no silently dropped
  schema keywords on the output path, typed errors everywhere (see the
  invariants in `CONTINUATION.md` §6).
- **Analyzer bar:** `dart analyze --fatal-infos` (pure packages) and
  `flutter analyze --fatal-infos --fatal-warnings` (plugin) must stay clean;
  all tests green: 145 at last validated baseline.

## Workflow

1. Fork / branch from `main`.
2. `flutter pub get` at the repo root (pub workspace — Flutter SDK required).
3. Run the validation commands from `CONTINUATION.md` §3 before and after.
4. Every non-trivial change updates docs in the same commit (parity matrix,
   protocol mapping, or the relevant phase spec).
5. Open a PR describing: scope, evidence (tests/smokes), and spec/doc deltas.

## Native work (macOS only)

Swift changes require macOS 27+, Xcode 27, and Apple Silicon. Point the
plugin at a local upstream checkout with
`export FOUNDATIONMODELS_SWIFT_PATH=/path/to/foundationmodels-js/swift`.
Keep the `ios/` and `macos/` copies of `FoundationModelsPlugin.swift`
byte-identical (`diff` them before committing).

## License

By contributing, you agree your contributions are licensed under the
project's license, **AGPL-3.0-only** (see [`LICENSE`](LICENSE)).
