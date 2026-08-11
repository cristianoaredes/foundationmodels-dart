# Plan Board — foundationmodels-dart

| ID | Título | Status |
|----|--------|--------|
| SPC-0001 | Phase 0 → streaming MVP | delivered |
| TCK-0018 | Full parity residual | done |
| TCK-0029 | Finish parity closeout | **done** |
| TCK-0045 | Post-closeout consumer readiness | **done** 2026-08-11 |
| residual-optin | TCK-0038/39/41 + 0028 reaffirm | **drained** 2026-08-11 |
| **TCK-0046** | Next-wave (consumer + content + gated) | **todo** — ready |

## Program status

**Post-closeout:** drained · **Residual opt-in:** drained · **Mirror:** `from: "1.0.4"`  
**Next-wave:** [NEXT-WAVE.md](../15-backlog/NEXT-WAVE.md) · [DES-0002](../16-designs/DES-0002-next-wave-program.md)

### Wave A — pull now

| Order | Ticket | Status | Notes |
|------:|--------|--------|-------|
| 1 | **TCK-0047** path contract docs (FND-0010) | todo | First `/ops-work` |
| 2 | **TCK-0048** chat-on-device Runner lipo | todo | Sibling consumer |
| 3 | **TCK-0052** pub.dev prep (no publish) | todo | SAFETY on real publish |

### Wave B — blocked (playbook ready)

| Ticket | Gate |
|--------|------|
| TCK-0049 MLX content | weights registered |
| TCK-0050 CoreAI content | monorepo + model |
| TCK-0051 live daemon binary | dyld/CoreAI fixed |

### Wave C — product / entitlement

| Ticket | Gate |
|--------|------|
| TCK-0053 MCP package | product opt-in |
| TCK-0028 PCC | entitlement U9 |

## Next command

```text
/ops-work TCK-0047
```
