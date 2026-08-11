# Post-closeout backlog — consumer readiness + ship

**Created:** 2026-08-11  
**Epic:** [TCK-0045](tickets/TCK-0045-epic-post-closeout-consumer-readiness.md)  
**Predecessor:** [CLOSEOUT.md](CLOSEOUT.md) · TCK-0029 **done** (RUN-20260811-closeout)  
**Baseline:** [`docs/parity.md`](../../docs/parity.md) · [`CONTINUATION.md`](../../CONTINUATION.md)

## Context

Parity **matrix closeout is complete** (honest `supported` / permanent limits / PCC blocked).  
What remains is **not** reopening closed cells — it is:

1. **Governança de entrega** (VER + materializar no git o que só existe local).
2. **Desbloquear consumidor iOS** (simulator build — FND-0009 / TCK-0042).
3. **Publicar mirror** com closeout (duplex) + guards iOS.
4. **Integração e adjacentes** sob demanda de produto.

## Already closed (do not re-open without new evidence)

| Epic / wave | Tickets | Notes |
|-------------|---------|--------|
| Residual | TCK-0001…0027 | FULL-PARITY drain |
| Closeout matrix | TCK-0029…0036 | duplex, instructions clean, Flutter live macOS, honest limits |
| Blocked | TCK-0028 PCC | entitlement only |

## Open program (ordered)

### Wave 0 — Ship hygiene (unblocks trust)

| ID | Prio | Effort | Gap | Done when | Executable now? |
|----|------|--------|-----|-----------|-----------------|
| **TCK-0043** | high | S | Closeout sem VER adversarial + estado só local | VER-20260811-closeout + checklist ship; docs/hand off consistent | **Yes** (read/write `.archagents` + git when operator allows) |

### Wave 1 — iOS consumer path (critical path)

| ID | Prio | Effort | Gap | Done when | Executable now? |
|----|------|--------|-----|-----------|-----------------|
| **TCK-0042** | high | M | iOS Simulator não compila Core (SecTask / OCRTool) | `flutter build ios --simulator` green (example ou chat-on-device path deps) | **Yes** (Swift Core + plugin docs) |
| **TCK-0044** | high | M | Mirror GitHub `1.0.2` sem duplex + sem guards iOS | Tag **1.0.3** (ou superior) publicada; plugin docs `from:` bump | After 0042 (or same PR if combined) |
| **TCK-0040** | medium | L | Sibling chat-on-device integração | App builds + unary/stream smoke (mock e/ou Apple) | After 0042 (+ 0044 if using published mirror) |

### Wave 2 — Product optional (not matrix) — **drained** 2026-08-11

| ID | Prio | Effort | Gap | Done when | Status |
|----|------|--------|-----|-----------|--------|
| **TCK-0038** | low | L | Daemon Unix-socket live E2E | dual-run **ou** env limit | **done** (fake peer + live env_limit) |
| **TCK-0039** | low | L | MCP agent client | smoke MCP **ou** won't-ship | **done** (won't ship MCP; agent green) |
| **TCK-0041** | low | M | pub.dev / `publish_to: none` | dry-run **ou** ADR stay-private | **done** (ADR-0002) |

See [RESIDUAL-OPTIN.md](RESIDUAL-OPTIN.md) · RUN-20260811-residual-optin.

### Wave 3 — External / gated (park)

| ID | Prio | Effort | Gap | Done when | Executable now? |
|----|------|--------|-----|-----------|-----------------|
| **TCK-0028** | low | L | PCC entitlement | blocked until Apple entitlement + smoke | **No** |
| MLX content `supported` | — | L | weights | dual-run content with registered model | Only with weights |
| CoreAI content `supported` | — | L | monorepo models | dual-run content | Only with registry |
| iOS FM on-device matrix | — | L | AI-capable device | dual-run on device | Not A14 iPad |

## Execution order (default)

```
1. TCK-0043  VER + ship hygiene (closeout)
2. TCK-0042  iOS sim Core guards + plugin docs
3. TCK-0044  mirror 1.0.3 publish (duplex + 0042)
4. TCK-0040  chat-on-device integration
5. TCK-0038 / 0039 / 0041  only if product asks
6. TCK-0028  only if entitlement appears
```

## Definition of Done (program TCK-0045)

- [x] TCK-0043 done (VER closeout exists; ship checklist recorded)
- [x] TCK-0042 done (iphonesimulator build evidence)
- [x] TCK-0044 done (mirror tag consumers can pin)
- [x] TCK-0040 done **or** explicitly deferred with consumer-owner note (package unblock; Runner lipo residual)
- [x] Findings FND-0009 closed; FND-0001…0006 reconciled (closed or supersedidos)
- [x] plan-board + CONTINUATION + AGENTS point at this program (not closeout Wave A)

## Autonomy / safety

- Level: **L2** project default; this drain executed under **L3 goal** for post-closeout.
- SAFETY: no secret/prod; git push/PR and pub.dev publish need explicit human intent when destructive/public.
- Parity honesty: never mark iOS FM `supported` from simulator-only build.

## How to start

```text
/ops-work TCK-0043    # recommended first if shipping the closeout branch
/ops-work TCK-0042    # critical path for consumer iOS
/ops-where            # dashboard
```
