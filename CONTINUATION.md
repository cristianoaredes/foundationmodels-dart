# CONTINUATION — how to pick up this project from any harness

**Read this first.** This file is the handoff contract for `foundationmodels-dart`. It exists so that any future session — another machine, another agent, another harness — can continue the work **without any prior conversational context**. Everything stated here was true at the commit it was added; verify against `git log` if it drifted.

> **TL;DR reading order:** this file → `docs/specs/adr-0001-flutter-adapter.md` → `docs/protocol-mapping.md` → `docs/parity.md` → phase specs under `docs/specs/` for residual work.

---

## 1. What this is

Dart/Flutter adapter for [FoundationModels JS](https://github.com/cristianoaredes/foundationmodels-js) — a bridge to **Apple Foundation Models** (on-device LLM, iOS 27+/macOS 27+, Apple Intelligence). The shared Swift core (`swift/FoundationModelsCore` + `swift/ios-bridge` in that monorepo) is the **single source of truth**; this repo is the *third adapter* over it (after the macOS JSON-RPC daemon and the React Native host). License: **AGPL-3.0-only**. Author: Cristiano Aredes.

## 2. Current state (snapshot, 2026-08-11)

| Area | Status | Evidence |
|------|--------|----------|
| `foundationmodels_platform_interface` | ✅ Done | RPC v2, stream events (incl. `tool_call_request`), typed errors; tests green |
| `foundationmodels` | ✅ Done | Runtime, mock, TransportProvider, tools duplex, cancel; 84 tests |
| `foundationmodels_apple` | ✅ Dart clean; Swift U1–U8 | `flutter analyze` clean; link via monorepo path **or** GitHub mirror |
| ios-bridge (upstream monorepo) | ✅ U1–U8 | `swift build` + host-native smokes |
| Host-native Apple Intelligence smokes | ✅ Measured | Mac17,9 · macOS 27 · Xcode 27 — availability, respond, stream+cancel, sessions, countTokens, guided, feedback, vision OCR+barcode, tools static (PARITY-42), instructions underA (not full A→B), multimodal honesty, MLX/CoreAI fail-closed |
| Parity (Flutter) | ✅ Closeout complete (honest) | `supported`: availability, respond, stream+cancel, sessions, instructions, guided, countTokens, feedback, vision OCR+barcode, **tools duplex**; Flutter live macOS E2E dual-run; multimodal partial (capability); MLX/CoreAI fail-closed; PCC blocked; iOS AI unsupported class on paired A14 iPad |
| CI workflows | ✅ Present | `.github/workflows/dart.yml` + `apple.yml` |
| Phases 3–8 packages | ✅ Present | policy, rag, eval, daemon, tools, agent, server, langchain |
| `foundationmodels-swift` mirror | ✅ Published | https://github.com/cristianoaredes/foundationmodels-swift **`from: "1.0.4"`** (stable SPM graph; CoreAI fail-closed stub) |
| Backlog | 🟡 Next-wave ready | Residual-optin drained; **NEXT-WAVE** epic TCK-0046 formalized (0047–0053 + 0028); see `.archagents/15-backlog/NEXT-WAVE.md` |

### codebase-ops

| Artefato | Path |
|----------|------|
| Contrato agentes | `AGENTS.md` |
| Plan board | `.archagents/12-inception/plan-board.md` |
| Backlog | `.archagents/15-backlog/backlog.csv` + `tickets/` |
| Residual drain run | `.archagents/13-execution/runs/RUN-20260811-residual-drain/` |
| Closeout run | `.archagents/13-execution/runs/RUN-20260811-closeout/` |
| Post-closeout program | `.archagents/15-backlog/POST-CLOSEOUT.md` |
| Residual opt-in run | `.archagents/13-execution/runs/RUN-20260811-residual-optin/` |
| Stay-private ADR | `.archagents/09-decisions/ADR-0002-stay-private-git-only.md` |
| Next-wave program | `.archagents/15-backlog/NEXT-WAVE.md` · DES-0002 |

## 3. How to validate

```bash
cd foundationmodels-dart
# Swift core path contract (TCK-0047 / FND-0010) — see packages/foundationmodels_apple/README.md
# Default (CI / consumers / iOS sim): leave FOUNDATIONMODELS_SWIFT_PATH unset → from: "1.0.4"
# Optional full CoreAI tip on Mac only:
#   export FOUNDATIONMODELS_SWIFT_PATH=/path/to/foundationmodels-js/swift
# Forbidden: point env at monorepo Core alone (SPM breaks on CoreAI deps).

flutter pub get
(cd packages/foundationmodels_platform_interface && dart test && dart analyze --fatal-infos)
(cd packages/foundationmodels && dart test && dart analyze --fatal-infos)
(cd packages/foundationmodels_apple && flutter analyze --fatal-infos)
(cd packages/foundationmodels_agent && dart test)
(cd packages/foundationmodels && dart test test/tools_e2e_test.dart)

# Remote SPM version resolve (mirror):
# see README in github.com/cristianoaredes/foundationmodels-swift
```

## 4. Unary-first + streaming (consumer guidance)

```dart
final fm = await createFoundationModels(); // mock offline if no Apple provider
final r = await fm.respond(input: 'Hello', instructions: 'Be brief.');

// Streaming + cancel work on mock and host-native Apple (parity: supported).
// Tools: stream(..., tools:, autoExecuteTools: true|false) — FmAgent uses false.
```

See `example/lib/main.dart`.

## 5. What to work on next

**Next-wave Wave A drained** (2026-08-11). Mirror pin: `from: "1.0.4"`.

| Wave | Tickets | Status |
|------|---------|--------|
| **A** | 0047 docs · 0048 Runner lipo · 0052 pub prep | **done** |
| **B gated** | 0049 MLX · 0050 CoreAI · 0051 live daemon | blocked until env/weights |
| **C product** | 0053 MCP · 0028 PCC · 0052 publish | product / entitlement / human |


## 6. Known quirks

- **Plugin `swift build` alone** needs Flutter modules; use monorepo bridge smoke or host app.
- **`FOUNDATIONMODELS_SWIFT_PATH` (FND-0010 closed via TCK-0047):** unset = mirror `from: "1.0.4"`; set = path containing **both** `FoundationModelsCore` + `ios-bridge` (mirror layout or monorepo `swift/` with CoreAI graph). Never Core alone.
- **`publish_to: none`** on all workspace packages — **ADR-0002 stay-private / git-only** (prep: TCK-0052).
- **Analyzer bar:** `--fatal-infos --fatal-warnings`.

## 7. Invariants (do not violate)

1. **No silent cloud fallback.** No provider → mock.
2. **Typed errors** via `error.data.code`; never fake success.
3. **`instructions` is a trusted channel** — never paste user/tool/web content into it.
4. **Fail-closed image allowlist.**
5. **Parity honesty** — `supported` only with measured evidence.
6. **Only streaming is truly interruptible** for cancel of generation.

## 8. Session log (reverse chronological)

- **2026-08-11** — Wave A L3 drain: TCK-0047 FND-0010 closed; TCK-0048 chat-on-device iOS sim **built** (Xcode 27 lipo multi-arch → ARCHS=arm64); TCK-0052 Phase 1 pub prep (no publish). RUN-20260811-wave-a.
- **2026-08-11** — Next-wave intake: epic TCK-0046 + tickets 0047–0053 (DoR/playbook-ready); TCK-0028 playbook enriched; program `NEXT-WAVE.md` / DES-0002.
- **2026-08-11** — Residual opt-in L3 drain: TCK-0038 daemon Unix-socket E2E (fake peer dual-run + live env_limit); TCK-0039 won't-ship MCP + agent tests green; TCK-0041 ADR-0002 stay-private; TCK-0028 PCC reaffirmed blocked; mirror docs pin **1.0.4**.
- **2026-08-11** — Post-closeout L3 drain complete: VER-closeout, iOS guards, mirror v1.0.3, duplex/instructions dual-run revalidated.
- **2026-08-11** — Post-closeout backlog formalized: epic TCK-0045, tickets 0043/0044, POST-CLOSEOUT.md, playbook 0042; next = 0043 → 0042 → 0044 → 0040.
- **2026-08-11** — Closeout drain complete (TCK-0029…0036): host duplex + instructions clean A→B; Flutter live macOS dual-run (avail/respond/stream-cancel/tools duplex); event alias + generationId fixes; iOS/MLX/CoreAI/multimodal honest limits; PCC blocked.
- **2026-08-11** — Residual drain: host-native smokes (availability/respond/stream+cancel); published foundationmodels-swift **v1.0.3** with stable SPM deps (CoreAI stub for `from:` graph); fixed v1.0.0/v1.0.1 revision pin failure.
- **2026-08-10** — Full backlog drain: pure-Dart packages phases 3–8, tools single-executor, ios-bridge U1–U8.
- **2026-08-09** — Initial scaffold: 3 packages, specs U1–U9 + phases 2–8.

## 9. Residuals closed (2026-08-11)

| Ticket | Resolution |
|--------|------------|
| TCK-0004 / TCK-0016 | Host-native Apple Intelligence smokes on MacBook Pro M5 Pro |
| TCK-0017 | Published foundationmodels-swift; use **v1.0.3** for SPM `from:` |
