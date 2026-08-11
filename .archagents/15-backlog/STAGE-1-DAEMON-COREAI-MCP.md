# Stage 1 backlog — Daemon · CoreAI · MCP

**Created:** 2026-08-11  
**Status:** formalized · ready for execute  
**Epic:** [TCK-0054](tickets/TCK-0054-epic-stage1-daemon-coreai-mcp.md)  
**Design:** [DES-0003](../16-designs/DES-0003-stage1-daemon-coreai-mcp.md)  
**Predecessor:** NEXT-WAVE Wave A drained · package v1 usable  
**Out of scope this stage:** MLX content (**Stage 2** = [TCK-0049](tickets/TCK-0049-mlx-content-when-weights.md)) · PCC · pub.dev publish

## Why these three

| Track | Why now | Effort shape |
|-------|---------|--------------|
| **Daemon live** | Client path already proven (TCK-0038 fake peer); gap is **real binary** dual-run | Small Dart + possible upstream env |
| **CoreAI content** | Fail-closed measured; mirror stub by design; gap is **monorepo content** honesty | Medium smoke + env, not rewrite Dart API |
| **MCP** | Tools + `FmAgent` exist; MCP is **new protocol surface**, product-approved for Stage 1 | Medium–L new package (mock-first) |

## Execution order (strict)

```text
1. TCK-0051  Daemon live binary E2E     (probe → fix env if needed → dual-run)
2. TCK-0050  CoreAI content dual-run    (monorepo probe → dual-run → parity note)
3. TCK-0055  MCP mini-spec (DES/spike)  (role, transport, security, package shape)
4. TCK-0053  MCP package implement      (mock-first; optional live)
```

**Rationale:** daemon and CoreAI are **closeout / evidence** on existing transports; MCP is greenfield and benefits from a frozen mini-spec first. Do not start 0053 before 0055 AC pass (or same PR with 0055 closed first).

## Track details

### 1 — Daemon (TCK-0051)

| Phase | Work | Exit |
|-------|------|------|
| **1a Probe** | Locate Release binary; ` --help` / start socket; record exit | `live_ok` or `env_limit` with reason |
| **1b Unblock env** (if needed) | Upstream monorepo rebuild / CoreAI link / document permanent limit | Binary usable **or** dated reaffirm blocked |
| **1c Dart E2E** | Gated test (`FM_DAEMON_BIN` / socket); dual-run health+respond; keep fake peer | dual_run live **or** blocked reaffirm |

**Does not:** claim Apple matrix cells `supported` from daemon-only path.

### 2 — CoreAI (TCK-0050)

| Phase | Work | Exit |
|-------|------|------|
| **2a Probe** | `FOUNDATIONMODELS_SWIFT_PATH` = monorepo `swift/`; SPM resolves CoreAI | graph ok **or** blocked with log |
| **2b Content** | Dual-run availability + respond with CoreAI model id; no system fallback | dual_run **or** blocked |
| **2c Honesty** | parity.md: monorepo vs mirror columns; mirror stays stub | docs synced |

**Does not:** put CoreAI into published mirror `from:` graph without full deps.

### 3 — MCP (TCK-0055 → TCK-0053)

| Phase | Work | Exit |
|-------|------|------|
| **3a Spec** (0055) | Client vs server; transport (default: stdio); tool map; security (`instructions` trusted) | DES or ticket body AC |
| **3b Package** (0053) | `foundationmodels_mcp` (or agreed name), `publish_to: none`, mock FM | tests green |
| **3c Optional live** | Smoke over Apple transport if available | evidence; not matrix cell |

**Does not:** rename `foundationmodels_agent` as MCP; ship cloud MCP gateway.

## Stage 2 (deferred — not Stage 1)

| ID | Title | When |
|----|-------|------|
| **TCK-0049** | MLX content when weights | After Stage 1 epic done **or** product pull |
| TCK-0028 | PCC | Entitlement |
| TCK-0052 Phase 2 | pub.dev publish | Human SAFETY |

## Program DoD (Stage 1)

- [ ] TCK-0051 done **or** reaffirmed blocked with dated evidence + reason  
- [ ] TCK-0050 done **or** reaffirmed blocked with dated evidence + reason  
- [ ] TCK-0055 done (mini-spec frozen)  
- [ ] TCK-0053 done (mock package + tests) **or** cancelled with product note  
- [ ] TCK-0049 remains Stage 2 (not started unless explicit override)  
- [ ] RUN + VER under `.archagents/13-execution/` / `14-verify/`  
- [ ] plan-board + CONTINUATION + NEXT-WAVE cross-links (P7)  

## Pull commands

```text
/ops-work TCK-0051    # Stage 1 first
/ops-work TCK-0050    # after 0051 closed or reaffirmed
/ops-work TCK-0055    # MCP spec (can parallelize after 0051 if two agents)
/ops-work TCK-0053    # only after 0055
```

**Parallelism (L3):** 0051 ∥ 0055 allowed; 0050 after monorepo free; 0053 after 0055 only.

## Effort envelope (honest)

| Track | If gates open | If gates closed |
|-------|---------------|-----------------|
| Daemon | S–M (1–2 sessions) | Reaffirm blocked (XS) |
| CoreAI | M (1–few sessions) | Reaffirm blocked (XS) |
| MCP | M–L (spec + package) | N/A — product approved for Stage 1 |
