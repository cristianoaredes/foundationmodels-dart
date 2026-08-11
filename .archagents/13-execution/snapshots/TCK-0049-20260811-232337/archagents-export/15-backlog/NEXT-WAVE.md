# Next-wave backlog — development readiness

**Created:** 2026-08-11  
**Status:** Wave A **drained** · **Stage 1 active** → see [STAGE-1-DAEMON-COREAI-MCP.md](STAGE-1-DAEMON-COREAI-MCP.md)  
**Epic:** [TCK-0046](tickets/TCK-0046-epic-next-wave-dev-ready.md)  
**Predecessor:** residual-optin drained · PR #2 merged · [RESIDUAL-OPTIN.md](RESIDUAL-OPTIN.md)  
**Design:** [DES-0002](../16-designs/DES-0002-next-wave-program.md)

## Goal

Convert every residual “next step” (open ticket + informal plan-board items)
into **tickets with DoR**, ordered waves, unblock conditions, and playbook-ready
work so an L2/L3 agent can `/ops-work TCK-NNNN` without re-discovery.

## Waves (execution order)

### Wave A — executable now (no external entitlement)

| Order | ID | Prio | Effort | Title | Executable? |
|------:|----|------|--------|-------|-------------|
| 1 | **TCK-0047** | high | S | FND-0010 path contract docs (monorepo vs mirror) | **Yes** |
| 2 | **TCK-0048** | high | M | chat-on-device Runner lipo / full sim build | **Yes** (sibling) |
| 3 | **TCK-0052** | medium | M | pub.dev prep (LICENSE/CHANGELOG/hosted deps) — no publish | **Yes** (prep only) |

### Stage 1 (active — Daemon · CoreAI · MCP)

Supersedes old Wave B/C ordering for these tracks. Full program: **STAGE-1-DAEMON-COREAI-MCP.md**.

| Order | ID | Prio | Title |
|------:|----|------|-------|
| 1 | **TCK-0051** | high | Daemon live E2E |
| 2 | **TCK-0050** | high | CoreAI content monorepo |
| 3 | **TCK-0055** | high | MCP mini-spec |
| 4 | **TCK-0053** | high | MCP package (after 0055) |

Epic: **TCK-0054**.

### Stage 2 / parked

| ID | Prio | Title | Notes |
|----|------|-------|-------|
| **TCK-0049** | low | MLX content | **Stage 2** — after Stage 1 |
| **TCK-0028** | low | PCC U9 | entitlement |
| **TCK-0052** publish | medium | Real pub.dev publish | human SAFETY |

## Inventory status

| ID | Status | Notes |
|----|--------|-------|
| TCK-0046 | todo | Wave A done; Stage 1 = TCK-0054 |
| TCK-0047 | **done** | FND-0010 closed |
| TCK-0048 | **done** | iOS sim Runner.app built |
| TCK-0049 | blocked | **Stage 2** MLX |
| TCK-0050 | **todo** high | Stage 1 #2 CoreAI |
| TCK-0051 | **todo** high | Stage 1 #1 daemon |
| TCK-0052 | **done** (Phase 1) | Phase 2 = human publish |
| TCK-0053 | **todo** high | Stage 1 #4 MCP impl (after 0055) |
| TCK-0054 | **todo** high | Epic Stage 1 |
| TCK-0055 | **todo** high | Stage 1 #3 MCP spec |
| TCK-0028 | blocked | PCC |

## Program DoD

- [x] Wave A done (0047, 0048, 0052-prep) — RUN-20260811-wave-a
- [ ] Wave B either done or reaffirmed blocked with dated evidence
- [ ] Wave C only advanced when gates open
- [x] plan-board + CONTINUATION synced (P7)
- [x] No silent cloud; parity honesty preserved

## Pull command

```text
/ops-work TCK-0051    # Stage 1 first (daemon)
# then TCK-0050 → TCK-0055 → TCK-0053
# Stage 2 MLX: TCK-0049 only after Stage 1 or override
```
