# Handoff — foundationmodels-dart

**Generated:** 2026-08-12 · harness: devin
**Snapshot:** `.archagents/13-execution/snapshots/TCK-0049-20260812-021636/`
**Resume:** `/ops-continue`

## Status atual

| Campo | Valor |
|-------|--------|
| Branch | `main` = `origin/main` |
| Commit | `6414cb8` (Merge PR #13 — UAB `/mcp` trailing-slash gotcha docs) |
| Working tree | **clean** |
| Default branch | `main` (no `develop`) |
| Open PRs | **0** |
| Extra branches | **none** |
| Backlog | **56 done · 2 blocked · 0 todo** (unchanged) |

## O que já foi feito (desde o último handoff, PR #12)

- [x] Retomada via `/ops-continue` — resume-over-restore (HEAD já batia com o snapshot anterior)
- [x] Snapshot redundante `TCK-0049-20260812-004346` removido (changes.patch vazio, sem trabalho único)
- [x] **Live MCP dual-run verificado end-to-end** contra UAB real (`uab.orqo.pro`, TCK-0059 harness) — antes só rodava em `env_limit` skip
  - `initialize` + `tools/list` (4 tools) + `callTool(codemode_list_apis)` OK em 2 rodadas
  - Token `UAB_HTTP_TOKEN` obtido via SSH (`hstgr-tve` → `/opt/uab/.env`), usado só em memória, nunca logado
- [x] Achado + documentado: UAB `POST /mcp` (sem barra) 307-redireciona para `http://.../mcp/` (downgrade de scheme, bug no lado do UAB); Dart `HttpClient` recusa seguir. Fix: usar `/mcp/` direto.
- [x] PR #13 aberto e **mergeado** (`docs/uab-mcp-trailing-slash-gotcha` → `main`), branch deletada
- [x] Gates externos reverificados nesta sessão: `FOUNDATIONMODELS_COREAI_MODELS`, `FM_MCP_SSE_URL`/`UAB_MCP_URL` — ainda `<unset>` fora desta sessão pontual

## Decisões

1. Git-only / `publish_to: none` — **ADR-0002**
2. MCP server + client both in `foundationmodels_mcp` (not replacing FmAgent)
3. MLX (TCK-0049) and PCC (TCK-0028) remain **blocked** until external gates
4. Consumer (chat-on-device) out of package remaining-work scope
5. UAB live test é verificação pontual (env-gated), não abriu ticket novo — documentado direto via PR de docs

## Bloqueios ativos

| ID | Gate |
|----|------|
| **TCK-0049** | MLX model weights registered |
| **TCK-0028** | Apple PCC entitlement |

## Próximo passo explícito

Nada L3-executável sem gate:

```bash
export FOUNDATIONMODELS_COREAI_MODELS=…   # MLX weights → then:
/ops-work TCK-0049
/ops-work TCK-0028                        # when PCC entitlement available
# Live MCP contra UAB já provado nesta sessão — reusar com:
export UAB_MCP_URL='https://uab.orqo.pro/mcp/'   # barra final obrigatória
export FM_MCP_BEARER=…                            # UAB_HTTP_TOKEN da VPS (hstgr-tve:/opt/uab/.env)
(cd packages/foundationmodels_mcp && dart test test/mcp_live_env_test.dart)
```

## Leitura obrigatória na retomada

1. `CONTINUATION.md` (seção 6, known quirks — inclui o gotcha do UAB agora)
2. `docs/PROJECT-STATUS.md`
3. `docs/DELIVERY-LOG.md`
4. `.archagents/15-backlog/OPEN-BACKLOG.md`
5. `docs/parity.md`
6. `packages/foundationmodels_mcp/README.md` (seção "UAB gotcha")

## Arquivos-chave

| Path | Why |
|------|-----|
| `packages/foundationmodels_mcp/` | Server + client + SSE; README com gotcha UAB |
| `packages/foundationmodels/` | Public API |
| `packages/foundationmodels_apple/` | Flutter plugin; path contract README |
| `docs/PROJECT-STATUS.md` | Narrative status |
| `CONTINUATION.md` | Known quirks atualizado |
| ADR-0002 | Stay-private |

## Contexto que expira

- Token UAB (`UAB_HTTP_TOKEN`) tem fingerprint `deec…392b` (64 chars) no momento desta sessão — reconfirmar se mudou antes de reusar o comando acima.
- Verificar de novo se `FOUNDATIONMODELS_COREAI_MODELS` / entitlement PCC abriram antes de assumir que continuam bloqueados.

## Snapshot contents

- `manifest.yaml` — ticket TCK-0049, branch main, commit 6414cb8, harness devin
- `git.bundle` · `changes.patch` (empty — working tree estava limpa) · `archagents-export/`
