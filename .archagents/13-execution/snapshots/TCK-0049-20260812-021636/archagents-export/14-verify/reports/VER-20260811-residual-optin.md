---
ver_id: VER-20260811-residual-optin
run: RUN-20260811-residual-optin
status: pass
date: 2026-08-11
---

# VER — residual opt-in L3 drain

## Scope check

| Ticket | Claim | Evidence | Verdict |
|--------|-------|----------|---------|
| TCK-0038 | Client dual-run + live env limit | daemon-socket-e2e.log; 4 tests pass | **pass** |
| TCK-0039 | Won't ship MCP; agent green | agent-tests.log; zero MCP package | **pass** |
| TCK-0041 | ADR stay-private | ADR-0002; dry-run fails expected | **pass** |
| TCK-0028 | Still blocked | ticket reaffirmed; no PCC smoke | **pass** (honest block) |

## Adversarial notes

1. **Fake peer ≠ production daemon** — accepted: live binary is env-limited; AC allows permanent env reason. Client path is what this repo owns.
2. **MCP honesty** — do not relabel `foundationmodels_agent` as MCP. Events are AG-UI-shaped tool loop only.
3. **No pub.dev publish** — dry-run only; SAFETY floor respected.
4. **Mirror pin** — Package.swift already `from: "1.0.4"`; docs synced (not a new publish in this run).

## Decision

**Ship-ready** for residual-optin branch: commit + PR to main. No production deploy.
