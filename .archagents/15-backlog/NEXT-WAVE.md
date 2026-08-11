# Next-wave backlog — development readiness

**Created:** 2026-08-11  
**Status:** Wave A **drained** (2026-08-11) · Wave B/C gated  
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

### Wave B — env / weights gate (playbook ready; start when gate opens)

| Order | ID | Prio | Effort | Title | Unblock when |
|------:|----|------|--------|-------|--------------|
| 4 | **TCK-0049** | medium | L | MLX content dual-run with registered weights | MLX model root + registry |
| 5 | **TCK-0050** | medium | L | CoreAI content dual-run (monorepo path) | monorepo tip + CoreAI model |
| 6 | **TCK-0051** | low | M | Live `foundationmodels-daemon` binary E2E | dyld/CoreAI daemon binary runs |

### Wave C — product / entitlement gate

| Order | ID | Prio | Effort | Title | Unblock when |
|------:|----|------|--------|-------|--------------|
| 7 | **TCK-0053** | low | L | MCP protocol package (opt-in) | explicit product request |
| 8 | **TCK-0028** | low | L | PCC U9 entitlement path | Apple PCC entitlement + profile |
| 9 | **TCK-0052** publish step | medium | S | Real `dart pub publish` | human SAFETY after prep green |

## Inventory status

| ID | Status | Notes |
|----|--------|-------|
| TCK-0046 | todo | Epic parent (Wave A children done) |
| TCK-0047 | **done** | FND-0010 closed |
| TCK-0048 | **done** | iOS sim Runner.app built |
| TCK-0049 | blocked | Weights gate |
| TCK-0050 | blocked | Monorepo+model gate |
| TCK-0051 | blocked | Daemon binary env gate |
| TCK-0052 | **done** (Phase 1) | Phase 2 = human publish |
| TCK-0053 | todo | Design-ready; product opt-in |
| TCK-0028 | blocked | Playbook enriched 2026-08-11 |

## Program DoD

- [x] Wave A done (0047, 0048, 0052-prep) — RUN-20260811-wave-a
- [ ] Wave B either done or reaffirmed blocked with dated evidence
- [ ] Wave C only advanced when gates open
- [x] plan-board + CONTINUATION synced (P7)
- [x] No silent cloud; parity honesty preserved

## Pull command

```text
# Wave A drained. Remaining:
/ops-work TCK-0049    # when MLX weights available
/ops-work TCK-0053    # only if product wants MCP
/ops-work TCK-0028    # only after entitlement
```
