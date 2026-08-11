# 00 — Overview

> **Status:** AS-IS bootstrap 2026-08-10 · phase 0 (spike)

## Elevator pitch

**foundationmodels-dart** é o adapter Dart/Flutter para o monorepo [FoundationModels JS](https://github.com/cristianoaredes/foundationmodels-js): expõe Apple Foundation Models (on-device) via canal JSON-RPC-shaped, com mock determinístico para CI. **Não** reimplementa lógica de modelo no Dart — o Swift core é a fonte da verdade.

## Estado do produto

| Camada | Estado |
|--------|--------|
| `foundationmodels_platform_interface` | Done (testes VM) |
| `foundationmodels` | Done (testes VM + mock) |
| `foundationmodels_apple` | Código escrito; **nunca compilado/rodado em device** |
| Phases 2–8 | Spec em `docs/specs/` — não implementadas |
| Upstream U1–U9 (ios-bridge) | Spec — depende de `foundationmodels-js` |

## Stack

- Dart **^3.12** · Flutter **≥ 3.27** (plugin Apple)
- Pub **workspace** (3 packages)
- Licença **AGPL-3.0-only**
- Platform target declarado: **iOS 27+ / macOS 27+**, Xcode 27

## Consumidores

- **chat-on-device** (`../chat-on-device`) — app de estudos que pinou este repo por git SHA e usa o adapter como primary LLM path (ADR-0004 no app).

## Fontes

- `README.md`, `CONTINUATION.md`
- `pubspec.yaml` (workspace)
- `packages/*`
