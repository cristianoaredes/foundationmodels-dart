# ADR-0002 — Stay private / git-only (no pub.dev publish)

- **Status:** aceito
- **Data:** 2026-08-11
- **Ticket:** TCK-0041
- **Related:** FND-0007, FND-0008

## Contexto

Todos os packages do workspace (`foundationmodels*`) declaram `publish_to: none`.
`dart pub publish --dry-run` em `foundationmodels` e `foundationmodels_agent` **falha**
por requisitos de publish (LICENSE por package root, path deps workspace, homepage/CHANGELOG).

Licença do monorepo: **AGPL-3.0-only** (FND-0008) — copiar para o grafo pub.dev
implica política de compliance de consumidores e não é gate de produto agora.

## Decisão

1. **Manter `publish_to: none`** em todos os packages do workspace.
2. Distribuição = **git** (este monorepo + mirror SPM `foundationmodels-swift`).
3. **Não** executar `dart pub publish` real sem gate humano + ADR de reabertura.
4. Dry-run documentado como evidência de **não-prontidão** intencional, não como bug.

## Consequências

- FND-0007 → **accepted / closed** (git-only by design).
- FND-0008 permanece **info** (AGPL policy awareness for future consumers).
- TCK-0041 → **done** via esta ADR (AC: explicit stay-private).
- Reabrir pub.dev exige novo ticket + checklist LICENSE/CHANGELOG/hosted deps + human SAFETY.

## Evidence

- `.archagents/13-execution/runs/RUN-20260811-residual-optin/evidence/pub-dry-run-foundationmodels.log`
- `.archagents/13-execution/runs/RUN-20260811-residual-optin/evidence/pub-dry-run-agent.log`
