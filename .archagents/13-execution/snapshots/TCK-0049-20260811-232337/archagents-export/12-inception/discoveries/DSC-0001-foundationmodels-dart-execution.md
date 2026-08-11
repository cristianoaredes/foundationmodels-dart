# DSC-0001 — Formalizar roadmap executável do foundationmodels-dart

- **Status:** capturada
- **Data:** 2026-08-10
- **Origem:** inventário `chat-on-device/FOUNDATIONMODELS-DART-GAPS.md` + `CONTINUATION.md`
- **Decisão:** governar o package com codebase-ops e transformar gaps em TCKs priorizados

## Hipóteses

1. Dart pure está estável o suficiente para freeze de contrato enquanto se desbloqueia Apple.
2. U1+U6 no `foundationmodels-js` são o caminho crítico para o chat streaming.
3. Até U1, path unary `respond` + mock devem ser first-class e documentados.

## Fontes

- `CONTINUATION.md`
- `docs/parity.md`
- `docs/specs/upstream-ios-bridge-extensions.md`
- `docs/specs/phase-2-streaming.md` … `phase-8-ecosystem.md`
- Sibling consumer: `../chat-on-device`

## Perguntas abertas

- [ ] Path local do monorepo `foundationmodels-js` neste Mac?
- [ ] Device alvo com iOS 27+ disponível?
- [ ] Quem implementa U1/U6 (este time vs outro harness)?
