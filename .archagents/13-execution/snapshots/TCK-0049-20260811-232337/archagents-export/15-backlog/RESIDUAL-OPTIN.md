# Residual opt-in backlog — post post-closeout

**Created:** 2026-08-11  
**Status:** **drained** (L3)  
**Predecessor:** [POST-CLOSEOUT.md](POST-CLOSEOUT.md) · TCK-0045 **done**  
**Run:** [RUN-20260811-residual-optin](../13-execution/runs/RUN-20260811-residual-optin/REPORT.md)

## Inventory (closed)

| ID | Status | Executable L3? | Outcome |
|----|--------|----------------|---------|
| **TCK-0038** | **done** | Yes | Fake-peer dual-run + live binary env_limit (dyld CoreAI) |
| **TCK-0039** | **done** | Partial | Won't ship MCP; agent/tools honesty + 7 tests green |
| **TCK-0041** | **done** | Dry-run yes | ADR-0002 stay-private; dry-run fails (expected) |
| **TCK-0028** | **blocked** | No | Reaffirmed 2026-08-11 — PCC U9 entitlement |

## Order executed

```
1. TCK-0038 daemon live  → done
2. TCK-0039 agent/MCP honesty → done
3. TCK-0041 pub.dev policy → done (ADR)
4. TCK-0028 reaffirm blocked → done
```

## Program DoD

- [x] Zero `todo` under 0038/0039/0041 (done or permanent limit with note)
- [x] TCK-0028 remains blocked with reaffirmation date
- [x] RUN + evidence under `.archagents/13-execution/runs/`
- [x] plan-board + CONTINUATION updated
