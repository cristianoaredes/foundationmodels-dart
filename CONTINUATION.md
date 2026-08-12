# CONTINUATION — how to pick up this project from any harness

**Read this first.** Handoff contract for `foundationmodels-dart`.  
True at the commit that last updated this file; verify with `git log` / `OPEN-BACKLOG.md` if drifted.

> **TL;DR:** this file → [`docs/PROJECT-STATUS.md`](docs/PROJECT-STATUS.md) → [`docs/parity.md`](docs/parity.md) → [`README.md`](README.md) → [`.archagents/15-backlog/OPEN-BACKLOG.md`](.archagents/15-backlog/OPEN-BACKLOG.md)

---

## 1. What this is

Dart/Flutter adapter for [FoundationModels JS](https://github.com/cristianoaredes/foundationmodels-js) — **Apple Foundation Models** (on-device) via shared Swift core. Third adapter after macOS daemon and RN host. License: **AGPL-3.0-only**.

---

## 2. Current state (2026-08-11, post L3 open drain + docs)

| Area | Status |
|------|--------|
| Core + interface + apple plugin | ✅ Done · parity closeout honest |
| Tools duplex / agent | ✅ Done · duplex **supported** |
| MCP server + client + SSE | ✅ `foundationmodels_mcp` · DES-0004/0005 · TCK-0053…0059 |
| Daemon client | ✅ Fake-peer E2E · live binary often dyld env_limit |
| Mirror SPM | ✅ `from: "1.0.4"` |
| pub.dev | ⏸ ADR-0002 stay-private |
| Backlog | **0 todo** · **2 blocked** (0049 MLX, 0028 PCC) |
| Git | `main` only · PRs #1–#11 merged · branches cleaned |

### codebase-ops map

| Artefato | Path |
|----------|------|
| Open backlog SoT | `.archagents/15-backlog/OPEN-BACKLOG.md` |
| Plan board | `.archagents/12-inception/plan-board.md` |
| Project status | `docs/PROJECT-STATUS.md` |
| Delivery log | `docs/DELIVERY-LOG.md` |
| ADR stay-private | `.archagents/09-decisions/ADR-0002-stay-private-git-only.md` |
| Stage 1 program | `.archagents/15-backlog/STAGE-1-DAEMON-COREAI-MCP.md` |
| Stage 2 MCP client | `.archagents/15-backlog/STAGE-2-MCP-CLIENT-SSE.md` |
| Handoff snapshot | `.archagents/13-execution/snapshots/TCK-0049-20260811-232337/` |
| Latest runs | `RUN-20260811-l3-open-drain`, `stage1`, `wave-a`, `residual-optin`, … |

---

## 3. How to validate

```bash
cd foundationmodels-dart
# Default Swift: leave FOUNDATIONMODELS_SWIFT_PATH unset → mirror 1.0.4
# Full monorepo tip: export FOUNDATIONMODELS_SWIFT_PATH=…/foundationmodels-js/swift
# Forbidden: monorepo Core alone (FND-0010 / TCK-0047)

dart pub get
(cd packages/foundationmodels_platform_interface && dart test && dart analyze --fatal-infos)
(cd packages/foundationmodels && dart test && dart analyze --fatal-infos)
(cd packages/foundationmodels_apple && flutter analyze --fatal-infos)
(cd packages/foundationmodels_agent && dart test)
(cd packages/foundationmodels_mcp && dart test)
(cd packages/foundationmodels_daemon && dart test)

# Live MCP (optional):
# export FM_MCP_SSE_URL=…   # or UAB_MCP_URL; optional FM_MCP_BEARER
# (cd packages/foundationmodels_mcp && dart test test/mcp_live_env_test.dart)
```

---

## 4. Consumer guidance

```dart
final fm = await createFoundationModels(); // mock if no Apple provider
final r = await fm.respond(input: 'Hello', instructions: 'Be brief.');
// stream + tools duplex measured on Apple path — see docs/parity.md
// FmAgent: package foundationmodels_agent
// MCP server/client: package foundationmodels_mcp
```

Example app: `example/`.

---

## 5. What to work on next

| Item | When |
|------|------|
| **TCK-0049** MLX content | weights registered |
| **TCK-0028** PCC | entitlement |
| Live MCP dual-run | `FM_MCP_SSE_URL` set |
| pub.dev | human SAFETY + ADR reopen |
| Live daemon binary | OS/CoreAI dyld fixed upstream |

Nothing else is L3-executable in this repo.

---

## 6. Known quirks

- Plugin `swift build` alone needs Flutter modules.  
- `FOUNDATIONMODELS_SWIFT_PATH`: both Core + ios-bridge; never Core alone.  
- All packages `publish_to: none`.  
- Analyzer: `--fatal-infos`.  
- Live daemon may crash dyld CoreAIRuntime on some hosts (client path still tested).  
- Live MCP against UAB: use `…/mcp/` (trailing slash). Bare `/mcp` 307-redirects to a scheme-downgraded `http://` Location (UAB-side issue), which Dart's `HttpClient` won't follow for POST — see `packages/foundationmodels_mcp/README.md`.  

---

## 7. Invariants

1. No silent cloud → mock if no provider.  
2. Typed errors `error.data.code`.  
3. `instructions` trusted channel.  
4. Fail-closed image allowlist.  
5. Parity honesty.  
6. Only streaming truly interruptible.  

---

## 8. Session log (reverse chronological)

- **2026-08-11** — Live MCP dual-run verified against real UAB endpoint (`uab.orqo.pro`, TCK-0059 harness, previously only `env_limit`-tested); found + documented the `/mcp` trailing-slash redirect gotcha.  
- **2026-08-11** — Full docs wave: PROJECT-STATUS, DELIVERY-LOG, MCP package README, CONTINUATION/README sync.  
- **2026-08-11** — Handoff snapshot PR #11; validation suite re-run (all green); gates still closed.  
- **2026-08-11** — L3 open drain PR #9; SSE Streamable-HTTP PR #10.  
- **2026-08-11** — Open backlog + MCP client PR #8; Stage 1 drain PR #6; README PR #7.  
- **2026-08-11** — Wave A, residual-optin, post-closeout, closeout drains (PRs #1–#4).  
- Earlier: full parity residual, phases 3–8 packages, U1–U8 bridge.  
