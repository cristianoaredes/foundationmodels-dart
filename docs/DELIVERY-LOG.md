# Delivery log — foundationmodels-dart (2026-08-11 wave)

Chronological **repo-only** delivery record for the closeout → L3 open drain line of work.  
Evidence lives under `.archagents/13-execution/runs/` and PR history on GitHub.

---

## Merged PRs (main)

| PR | Title | Outcome |
|----|--------|---------|
| #1 | Post-closeout L3 | duplex fail-closed, iOS sim guards path, mirror ≥1.0.3 |
| #2 | Residual opt-in | daemon fake-peer E2E, MCP honesty, ADR-0002 stay-private |
| #3 | Next-wave intake | TCK-0046… formalization |
| #4 | Wave A drain | FND-0010 docs, chat-on-device lipo notes, pub prep |
| #5 | Stage 1 backlog formalize | daemon · CoreAI · MCP program |
| #6 | Stage 1 drain | `foundationmodels_mcp` **server**, CoreAI/daemon env honesty |
| #7 | README v1 complete | public docs rewrite |
| #8 | Open backlog + MCP client | client, SSE, DES-0005, TCK-0056…0059 formal |
| #9 | L3 open drain | TCK-0059 env harness; reaffirm MLX/PCC blocked |
| #10 | Streamable-HTTP SSE | `event:` + `data:` body detection |
| #11 | Handoff snapshot | cross-harness snapshot TCK-0049-20260811-232337 |

---

## Runs & verifies

| Run | VER | Scope |
|-----|-----|--------|
| RUN-20260811-closeout | VER-closeout | matrix closeout |
| RUN-20260811-post-closeout | — | consumer readiness |
| RUN-20260811-residual-optin | VER-residual-optin | 0038/39/41 |
| RUN-20260811-wave-a | VER-wave-a | 0047/48/52 |
| RUN-20260811-stage1 | VER-stage1 | 0050/51/53/54/55 |
| RUN-20260811-open-backlog | — | formalize open set |
| RUN-20260811-l3-open-drain | VER-l3-open-drain | 0059 + reaffirms |

---

## ADRs / designs

| ID | Topic |
|----|--------|
| ADR-0001 | codebase-ops bootstrap (local) |
| ADR-0002 | stay-private / git-only (no pub.dev) |
| DES-0002 | next-wave program |
| DES-0003 | Stage 1 daemon · CoreAI · MCP |
| DES-0004 | MCP **server** package |
| DES-0005 | MCP **client** + SSE |

---

## Final ticket ledger (non-done only)

| ID | Status | Gate |
|----|--------|------|
| TCK-0049 | blocked | MLX weights |
| TCK-0028 | blocked | PCC entitlement |

All other TCKs in CSV: **done**.

---

## Packages introduced / matured this wave

- Matured: `foundationmodels_*` core + apple + tools + agent + daemon  
- **New:** `foundationmodels_mcp` (server + client + SSE + live env test)  
