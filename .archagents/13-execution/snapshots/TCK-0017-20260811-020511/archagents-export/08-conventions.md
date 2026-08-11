# 08 — Conventions

| Dimensão | Convenção |
|----------|-----------|
| Layout | Pub workspace Dart 3.12+ · 3 packages |
| API pública | `package:foundationmodels` only para apps |
| Transport | Factory `createFoundationModelsAppleTransport()` — sem singleton estático |
| Analyzer | `--fatal-infos --fatal-warnings` |
| Testes | VM para pure-Dart; Flutter analyze no apple |
| Specs | `docs/specs/phase-*.md` + upstream U* |
| Handoff | `CONTINUATION.md` na raiz (manter vivo) |
| Commits | Temáticos; CI drafts não em `.github/` até token com scope |

## Consumidor

App não deve importar `foundationmodels_apple` fora do wiring de DI/data; preferir `createFoundationModels(providers: [...])`.
