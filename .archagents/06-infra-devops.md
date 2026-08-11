# 06 — Infra / DevOps

## CI

| Item | Status |
|------|--------|
| `.github/workflows/` | **Ausente** no repo (token OAuth sem scope workflow) |
| Drafts | `docs/ci/dart.yml`, `docs/ci/apple.yml` |
| Validação local | `flutter pub get` + dart test/analyze por package |

## Ambientes

| Env | Uso |
|-----|-----|
| Linux/CI | Pure-Dart + mock |
| macOS 27 + Xcode 27 + Apple Silicon | Compile plugin + device smoke (phase 2) |

## Dev link Swift

```bash
export FOUNDATIONMODELS_SWIFT_PATH=/path/to/foundationmodels-js/swift
```
