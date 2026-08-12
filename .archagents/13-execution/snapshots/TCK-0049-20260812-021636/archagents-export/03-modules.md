# 03 — Modules

| Módulo | Path | Papel | Depende de |
|--------|------|-------|------------|
| workspace root | `pubspec.yaml` | Pub workspace | 3 packages |
| foundationmodels | `packages/foundationmodels/` | API pública + mock + sessions | platform_interface |
| platform_interface | `packages/foundationmodels_platform_interface/` | Transport, events, errors, models | (none Dart) |
| foundationmodels_apple | `packages/foundationmodels_apple/` | Plugin iOS/macOS SPM | platform_interface, Flutter |
| specs | `docs/specs/` | Fases 2–8 + U1–U9 | — |
| parity | `docs/parity.md` | Matriz de capacidade | — |
| CI drafts | `docs/ci/` | Workflows não instalados em `.github/` | — |

## Entry points

- `createFoundationModels({providers})` — `packages/foundationmodels/lib/src/runtime.dart`
- `createFoundationModelsAppleTransport()` — `packages/foundationmodels_apple/lib/src/foundationmodels_apple.dart`

## Evidência de volume

- ~31 arquivos Dart · ~4 Swift · 11 `*_test.dart` (145 testes declarados no CONTINUATION)
