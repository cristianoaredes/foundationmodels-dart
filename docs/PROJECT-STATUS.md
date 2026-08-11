# Project status — foundationmodels-dart

**As of:** 2026-08-11 · **HEAD (at write):** see `git rev-parse HEAD` (docs ship may lag one PR)  
**Default branch:** `main` only (no `develop`)  
**License:** AGPL-3.0-only · **Distribution:** git-only (ADR-0002)

This document is the **narrative project status** for humans and agents.  
Operational SoT: [`.archagents/15-backlog/OPEN-BACKLOG.md`](../.archagents/15-backlog/OPEN-BACKLOG.md) · handoff: [`CONTINUATION.md`](../CONTINUATION.md) · public entry: [`README.md`](../README.md).

---

## 1. What shipped (v1 package)

### 1.1 Core adapter

| Package | Role | State |
|---------|------|--------|
| `foundationmodels` | Public API: respond, stream, sessions, schema, tools, mock, cancel | Done · VM tests green |
| `foundationmodels_platform_interface` | RPC v2, stream events, typed errors | Done · ~58 tests |
| `foundationmodels_apple` | Flutter plugin iOS/macOS → Swift Core/Bridge | Done · live macOS + host smokes measured |

**SPM pin:** [foundationmodels-swift](https://github.com/cristianoaredes/foundationmodels-swift) **`from: "1.0.4"`** (CoreAI stubbed/excluded for stable `from:` graph).

**Path contract (TCK-0047 / FND-0010):**  
unset env → mirror; set env only to path with **both** `FoundationModelsCore` + `ios-bridge` (mirror layout or full monorepo `swift/`). Never Core alone.

### 1.2 Tools & agent

| Package | Role | State |
|---------|------|--------|
| `foundationmodels_tools` | `FmToolRouter` duplex | Done |
| `foundationmodels_agent` | `FmAgent` tool loop, HITL, AG-UI-shaped events | Done · 7 tests |

Parity: **tools duplex = `supported`** (host dual-run + Flutter live macOS).

### 1.3 MCP (`foundationmodels_mcp`)

| Surface | Spec | State |
|---------|------|--------|
| **Server** (stdio NDJSON) | DES-0004 | Done — `FmMcpServer`, `fm_respond`, tools/list|call |
| **Client** + loopback | DES-0005 | Done — `FmMcpClient`, `listToolsAsFmTools` |
| **SSE transport** | DES-0005 | Done — `McpSseTransport`, `parseSseDataFrames`, Streamable-HTTP `event:`+`data:` |
| **Live remote** | TCK-0059 | Harness env-gated (`FM_MCP_SSE_URL` / `UAB_MCP_URL`); skips if unset |

**Not** a replacement for `FmAgent`. **Not** Apple matrix parity.

### 1.4 Ecosystem packages

| Package | Role | State |
|---------|------|--------|
| `foundationmodels_daemon` | Unix-socket client | Done · fake-peer E2E; live binary often dyld/CoreAI env_limit |
| `foundationmodels_policy` | PII redaction | Present |
| `foundationmodels_rag` | Local semantic index | Present |
| `foundationmodels_eval` | Eval + traces | Present |
| `foundationmodels_server` | OpenAI-shaped HTTP | Present |
| `foundationmodels_langchain` | LangChain.dart adapter | Present |

All: `publish_to: none`.

### 1.5 Parity (honest)

See [`docs/parity.md`](parity.md). Highlights:

- **supported:** availability, respond, stream+cancel, sessions, instructions, guided, countTokens, feedback, vision OCR/barcode, **tools duplex**
- **partial:** multimodal (capability-limited on `apple.system`)
- **fail-closed / not measured:** MLX, CoreAI content without registry
- **blocked:** PCC (entitlement)

---

## 2. Program history (codebase-ops)

| Program | Tickets / result | Key PRs / runs |
|---------|------------------|----------------|
| Full parity residual | TCK-0018… | closeout runs |
| Closeout | TCK-0029…0036 | RUN-20260811-closeout |
| Post-closeout | TCK-0042…0045 | PR #1 |
| Residual opt-in | TCK-0038/39/41 | PR #2 |
| Next-wave intake + Wave A | TCK-0046…0048, 0052 | PR #3–#4 |
| Stage 1 daemon/CoreAI/MCP server | TCK-0050…0055 | PR #5–#6 |
| README v1 | — | PR #7 |
| Open backlog + MCP client | TCK-0056…0058 | PR #8 |
| L3 open drain | TCK-0059 + reaffirm 0049/0028 | PR #9 |
| SSE Streamable-HTTP | transport fix | PR #10 |
| Handoff snapshot | snapshot dir | PR #11 |

**Backlog counts (final):** ~56 **done** · **2 blocked** · **0 todo**.

---

## 3. What remains (this repo only)

| ID | Status | Unblock |
|----|--------|---------|
| **TCK-0049** | blocked | MLX weights + registry |
| **TCK-0028** | blocked | Apple PCC entitlement |
| pub.dev Phase 2 | human SAFETY | ADR-0002 reopen + human `dart pub publish` |

**Executable L3 work:** exhausted.

### Live MCP smoke (when URL exists)

```bash
export FM_MCP_SSE_URL='https://…'   # or UAB_MCP_URL
# optional: export FM_MCP_BEARER='…'
cd packages/foundationmodels_mcp && dart test
```

### Known env limits (documented, not open bugs)

| Item | Symptom |
|------|---------|
| Live `foundationmodels-daemon` | dyld missing CoreAIRuntime symbol (OS skew) |
| CoreAI content | no registered AIModel → not measured |
| iOS sim consumer | package OK; app tooling was class-A lipo (fixed in chat-on-device) |

---

## 4. How to validate

```bash
cd foundationmodels-dart
dart pub get   # workspace root

(cd packages/foundationmodels_platform_interface && dart test && dart analyze --fatal-infos)
(cd packages/foundationmodels && dart test && dart analyze --fatal-infos)
(cd packages/foundationmodels_apple && flutter analyze --fatal-infos)
(cd packages/foundationmodels_agent && dart test)
(cd packages/foundationmodels_mcp && dart test)
(cd packages/foundationmodels_daemon && dart test)
```

CI: `.github/workflows/dart.yml`.

---

## 5. Invariants

1. No silent cloud fallback → mock if no provider.  
2. Typed errors via `error.data.code`.  
3. `instructions` is trusted — never paste untrusted content.  
4. Fail-closed image allowlist.  
5. Parity honesty — `supported` only with evidence.  
6. Only streaming is truly interruptible for cancel.  

---

## 6. Doc map

| Doc | Purpose |
|-----|---------|
| [`README.md`](../README.md) | Public overview + quick start |
| [`CONTINUATION.md`](../CONTINUATION.md) | Agent/human handoff contract |
| [`docs/parity.md`](parity.md) | Capability matrix |
| [`docs/protocol-mapping.md`](protocol-mapping.md) | Protocol mapping |
| [`docs/PROJECT-STATUS.md`](PROJECT-STATUS.md) | **This file** — narrative status |
| [`.archagents/15-backlog/OPEN-BACKLOG.md`](../.archagents/15-backlog/OPEN-BACKLOG.md) | Open tickets SoT |
| [`.archagents/12-inception/plan-board.md`](../.archagents/12-inception/plan-board.md) | Plan board |
| DES-0002…0005 | Designs (next-wave, stage1, MCP server/client) |
| Snapshot | `.archagents/13-execution/snapshots/TCK-0049-20260811-232337/` |

---

## 7. Git hygiene

- Default branch: **main**  
- Topic branches cleaned after merge  
- PRs #1–#11 merged (as of handoff snapshot ship)  
