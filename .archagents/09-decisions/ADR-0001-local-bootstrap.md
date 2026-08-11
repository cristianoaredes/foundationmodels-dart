# ADR-0001 — Bootstrap codebase-ops neste repositório

- **Status:** aceito
- **Data:** 2026-08-10

## Contexto

O package já tinha `CONTINUATION.md`, specs e parity, mas **sem** ciclo Intake→Execute governado. O consumidor `chat-on-device` formalizou gaps em MD na raiz do app; o trabalho de desbloqueio precisa viver **neste** repo.

## Decisão

1. Instalar `.archagents/` + `AGENTS.md` (codebase-ops).
2. Compilar DSC-0001 / SPC-0001 e backlog TCK a partir do inventário de gaps.
3. Manter `CONTINUATION.md` como handoff técnico; `.archagents/` como estado operacional.
4. Upstream design do adapter permanece em `docs/specs/adr-0001-flutter-adapter.md` (não renumerar).

## Consequências

- Trabalho futuro via `/ops-work` / tickets.
- Cross-repo U1/U6 explícitos nos tickets.
