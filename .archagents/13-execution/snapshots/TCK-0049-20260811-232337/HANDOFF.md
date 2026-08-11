# Handoff — foundationmodels-dart session

**Generated:** 2026-08-11T23:23:38Z · harness: grok  
**Snapshot:** `.archagents/13-execution/snapshots/TCK-0049-20260811-232337/`  
**Resume:** `/ops-continue` or restore from this directory

## Status atual

| Campo | Valor |
|-------|--------|
| Branch | `main` (= `origin/main`) |
| Commit | `fd88e04` (Merge PR #10) |
| Working tree | **clean** |
| Default branch | `main` (no `develop`) |
| Open PRs | **0** |
| Extra branches | **none** (only main) |
| Autonomy | L2 granted · last work L3 drains |

## O que já foi feito (esta linha de trabalho)

- [x] Package v1 shippable (parity closeout, tools duplex, agent, mirror 1.0.4)
- [x] Residual-optin + Wave A + Stage 1 (daemon/CoreAI/MCP server) drained · PRs #1–#6
- [x] README full rewrite · PR #7
- [x] Open backlog formalized + MCP client/SSE · PR #8
- [x] L3 open drain (0059 live harness; MLX/PCC reaffirm) · PR #9
- [x] Streamable-HTTP SSE detect · PR #10
- [x] Branch cleanup (remote topic branches pruned)

## Decisões tomadas

1. **Git-only distribution** — ADR-0002 stay-private (`publish_to: none`)
2. **MCP server** (DES-0004) + **MCP client** (DES-0005) both in `foundationmodels_mcp`
3. **MLX deferred / blocked** until weights (TCK-0049)
4. **PCC stays blocked** without entitlement (TCK-0028)
5. Consumer app (chat-on-device) **out of package scope** for remaining work

## Bloqueios ativos

| ID | Status | Gate |
|----|--------|------|
| **TCK-0049** | blocked | MLX model weights registered |
| **TCK-0028** | blocked | `com.apple.developer.private-cloud-compute` |

Zero `todo`. pub.dev Phase 2 = human SAFETY only.

## Próximo passo explícito

Nothing executable without external gate:

```bash
# When UAB live:
export FM_MCP_SSE_URL='https://…'   # optional FM_MCP_BEARER
(cd packages/foundationmodels_mcp && dart test)

# When weights / entitlement:
/ops-work TCK-0049
/ops-work TCK-0028
```

## Contexto que expira

- Live daemon binary still dyld/CoreAI-skew on host (env_limit; client fake-peer OK)
- CoreAI content not measured without AIModel
- `chat-on-device` may have separate WIP — not in this snapshot scope

## Arquivos-chave

| Path | Why |
|------|-----|
| `README.md` | Full v1 map |
| `CONTINUATION.md` | Handoff contract |
| `.archagents/15-backlog/OPEN-BACKLOG.md` | Open set SoT |
| `packages/foundationmodels_mcp/` | Server + client MCP |
| `docs/parity.md` | Capability honesty |
| `.archagents/09-decisions/ADR-0002-stay-private-git-only.md` | No pub.dev |

## Snapshot contents

- `manifest.yaml` — ticket TCK-0049 (auto-detected non-done), branch, commit
- `git.bundle` — compact branch bundle
- `changes.patch` — empty (clean tree)
- `archagents-export/` — selective `.archagents/`

## Restore

```bash
# From project root in new harness:
/ops-continue
# or restore-snapshot.sh pointing at this directory
```
