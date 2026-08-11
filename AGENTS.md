# AGENTS.md — foundationmodels-dart

## Identidade

**foundationmodels-dart** — adapter Dart/Flutter para Apple Foundation Models via Swift core compartilhado (`foundationmodels-js`). Pub workspace: `foundationmodels` + `foundationmodels_platform_interface` + `foundationmodels_apple`. Licença AGPL-3.0-only. Closeout matrix done (host + Flutter live macOS); post-closeout: iOS sim + mirror + ship (TCK-0045).

Governado por **codebase-ops**. Fonte operacional: [`.archagents/README.md`](.archagents/README.md). Handoff técnico legado: [`CONTINUATION.md`](CONTINUATION.md).

## Convenções

- IDs: `DSC/SPC/TCK/DES/RUN/VER/ADR/FND` monotônicos sob `.archagents/`.
- Gates: Intake → Triage → Design → Execute → Verify → Ship.
- **P7:** estágio não termina sem atualizar docs afetadas.
- **Evidence (P2):** citar `path:Lstart-Lend`.
- **Parity honesty:** nunca marcar capability `supported` sem smoke on-device.
- **No silent cloud.** Mock se Apple indisponível.
- Só `packages/foundationmodels` é API pública de app; apple = transport.

## Comandos

| Comando | Uso |
|---------|-----|
| `/ops-work` | Próximo ticket ou ciclo completo |
| `/ops-where` | Status do backlog |
| `/ops-continue` | Retomar |
| `/ops-spec` | Nova spec |
| `/ops-ship` | Verify + entrega |
| `/ops-config` | Bootstrap/drift/docs |

## Autonomia

| Nível | Flag |
|-------|------|
| L0 Manual | `--manual` |
| L1 Assisted | `--assist` |
| **L2 Autonomous (default)** | `--yolo` |
| L3 Continuous | `--auto` |

**Concedido neste projeto:** `L2`. SAFETY floor inegociável.

<!-- codebase-ops:proactive:start -->
## Acionamento Proativo (codebase-ops)

| Gatilho | Ação |
|---------|------|
| documentar / bug / planejar / executar / verificar | Roteie `/ops-*` |
| backlog com ticket não-done | Ofereça `/ops-continue` ou `/ops-work` |
| ANTES de editar plugin Apple / transport / security | Consulte `07-security-compliance.md` + CONTINUATION invariantes |
| APÓS mudança significativa | Atualize `.archagents/` e `CONTINUATION.md` se status mudar |
| Detectou gap upstream js | Ticket com `external_refs` — não silencie |

**Autonomia concedida:** `L2`
<!-- codebase-ops:proactive:end -->

## Project conventions (quick)

- Workspace: `flutter pub get` na raiz.
- Validar: ver `.archagents/10-runbooks.md`.
- Specs de fase: `docs/specs/phase-*.md` e `upstream-ios-bridge-extensions.md`.
- Consumidor de referência: sibling `../chat-on-device`.
- Mirror **v1.0.4**. **Stage 1 active:** daemon → CoreAI → MCP (TCK-0054). MLX Stage 2. See `STAGE-1-DAEMON-COREAI-MCP.md`.

## Docs

- Overview: `.archagents/00-overview.md`
- Plan board: `.archagents/12-inception/plan-board.md`
- Backlog: `.archagents/15-backlog/backlog.csv`
