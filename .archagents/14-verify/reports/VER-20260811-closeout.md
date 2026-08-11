---
ver_id: VER-20260811-closeout
run_id: RUN-20260811-closeout
ticket: TCK-0029
related: [TCK-0043]
status: pass
created_at: 2026-08-11T18:00:00-03:00
independence: adversarial-post-run
---

# VER-20260811-closeout

Independent verification of closeout drain (post-execution).

## Method

- Evidence files must exist on disk under RUN evidence dir.
- Claims of dual-run must appear in log content (not empty placeholders).
- Pure-Dart packages re-executed this verify session (exit 0).
- No soft-pass: `supported` cells only with measured or permanent-limit notes.

## Evidence inventory

| File | Present | Spot-check |
|------|---------|------------|
| `evidence/duplex.log` | yes | `tools_duplex_ok=true`, dual_run |
| `evidence/instructions2.log` | yes | underB_clean / instructions path |
| `evidence/flutter_live_run8.log` | yes | `SMOKE_RC:0`, stream_cancel + tools_duplex dual |

Path root: `.archagents/13-execution/runs/RUN-20260811-closeout/evidence/`

## Pure-Dart re-run (this session)

| Package | Result | Log |
|---------|--------|-----|
| foundationmodels_platform_interface | **58 passed** | implementer scratch `dart-tests-platform.log` |
| foundationmodels | **86 passed** | implementer scratch `dart-tests-foundation.log` |

## Parity honesty

- Tools duplex + instructions promoted only with dual-run evidence (RUN report + logs).
- Multimodal remains partial (capability).
- MLX/CoreAI fail-closed permanent without registry.
- iOS FM not measured (A14 class limit).
- PCC remains blocked.

## Ship decision

| Option | Decision |
|--------|----------|
| Local hold only | — |
| **PR opened** | **Yes** — https://github.com/cristianoaredes/foundationmodels-dart/pull/1 · mirror tag https://github.com/cristianoaredes/foundationmodels-swift/releases/tag/v1.0.3 |

Criterion: code and ops artifacts must be on a reviewable branch; force-push forbidden.

## Verdict

**PASS** for RUN-20260811-closeout claims against local evidence + dual pure-Dart green.

## Residual (not VER fail)

- TCK-0042/0044/0040 are **post-closeout** program (TCK-0045), not regress of closeout matrix.
- Mirror still 1.0.2 until TCK-0044.
