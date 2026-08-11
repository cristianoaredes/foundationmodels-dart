# DES-0002 — Next-wave program (dev-ready backlog)

- **Status:** approved for intake → execute  
- **Date:** 2026-08-11  
- **Epic:** TCK-0046  
- **Program:** [NEXT-WAVE.md](../15-backlog/NEXT-WAVE.md)

## Context

After residual-optin drain, formal backlog had only **TCK-0028 blocked** and
several informal “next” items on the plan-board. This design freezes them into
ordered, DoR-complete tickets.

## Principles

1. **Honesty first** — blocked stays blocked until gate evidence; no fake `supported`.
2. **Repo ownership** — chat-on-device work is sibling-owned; this repo tracks interface + docs + package regressions only.
3. **SAFETY** — real `dart pub publish` and secret/entitlement ops require human gate.
4. **Reopen ≠ rewrite** — MLX/CoreAI content tickets supersede permanent-limit closures of TCK-0033/0034 only when weights exist.

## Wave A design notes

| Ticket | Approach | Primary surfaces |
|--------|----------|------------------|
| 0047 | Document path contract in plugin README + CONTINUATION + maybe Package.swift comments; close FND-0010 | `packages/foundationmodels_apple/README.md`, CONTINUATION |
| 0048 | Reproduce lipo error on chat-on-device; fix Flutter clean/rebuild/arch or Xcode config in **consumer**; package only if root cause is plugin | `../chat-on-device`, optional plugin docs |
| 0052 prep | Per-package LICENSE symlink/copy, CHANGELOG, repository field, path→version strategy doc; keep `publish_to: none` until publish gate | all `packages/*/pubspec.yaml` |

## Wave B design notes

| Ticket | Approach |
|--------|----------|
| 0049 | Register MLX via Core env; dual-run availability+respond with `model:`; no system fallback |
| 0050 | Only with `FOUNDATIONMODELS_SWIFT_PATH` monorepo; mirror remains CoreAI-stubbed |
| 0051 | When daemon binary `--help`/health exits 0, run real socket dual-run vs TCK-0038 fake peer |

## Wave C design notes

| Ticket | Approach |
|--------|----------|
| 0053 | New package or subdir MCP client; mock FM first; never claim matrix parity |
| 0028 | Entitlement → smoke `apple.pcc` → parity cell promote only with evidence |
| 0052 publish | After prep: human `dart pub publish` per package; AGPL disclosure |

## Non-goals

- Reopening closed matrix cells without new evidence  
- Silent cloud fallback  
- Force-publishing packages under ADR-0002 without reopening ADR  

## Risks

| Risk | Mitigation |
|------|------------|
| Consumer work conflated with package | 0048 AC separates package vs Runner |
| Weights never arrive | 0049/0050 stay blocked; reaffirm annually |
| pub.dev AGPL surprise | FND-0008 callout in 0052 AC |
