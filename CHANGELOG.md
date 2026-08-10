# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added — initial scaffold (phases 0–1 of ADR-0001)

- `foundationmodels_platform_interface`: RPC v2 envelope transport contract
  (`FoundationModelsTransport`), 15 method constants, 10 sealed stream event
  types, 27 typed exceptions mapped 1:1 from the upstream stable
  `error.data.code` table, `AvailabilityReport` / `Usage` / `TokenCount`
  models. 53 tests.
- `foundationmodels`: high-level runtime — `classify`, `extract`, `rank`,
  `summarize`, `respond`, `stream`, lazy sessions (first-request-wins,
  `transition`, `dispose`), `FmSchema` with `SchemaMode.output` (fail-fast)
  and `SchemaMode.tool` (sanitize), `CancelToken`, `contextPolicy: guard`,
  deterministic offline mock provider. 92 tests.
- `foundationmodels_apple`: federated iOS+macOS plugin (SPM) — envelope
  router `foundationmodels/rpc`, multiplexed stream channel
  `foundationmodels/streams`, cooperative cancellation. Swift code targets
  the upstream ios-bridge extensions U1–U7 (see
  `docs/specs/upstream-ios-bridge-extensions.md`); not yet compiled.
- Repo meta: ADR-0001 + implementation specs for phases 2–8
  (`docs/specs/`), parity matrix, protocol mapping, continuation handoff.

### Fixed

- Stream `error` event now uses the flat canonical shape
  (`code`/`message`/`data` at top level) matching the Dart `StreamError`
  parser — previously every stream error would have degraded to
  `UnknownModelException`.

[Unreleased]: https://github.com/cristianoaredes/foundationmodels-dart/commits/main
