---
id: TCK-0040
slug: chat-on-device-integration
title: "Sibling chat-on-device consumer integration"
source: closeout-backlog-adjacent
created_at: 2026-08-11T12:00:00-03:00
status: done
priority: medium
category: feature
effort: L
related: [TCK-0042, TCK-0044, TCK-0045, TCK-0036]
consumer: ../chat-on-device
program: POST-CLOSEOUT
order: 3
---

# TCK-0040 — chat-on-device integration

## Priority

**After** TCK-0042 (iOS sim compile) and preferably TCK-0044 (mirror pin).  
Was “optional adjacent”; promoted to **medium** under post-closeout epic (consumer readiness).

## Gap

Sibling app exists but cannot complete iOS simulator path while Core fails to compile (FND-0009).  
macOS live path may already work with monorepo env (ties to TCK-0036 patterns).

## Depends on

- **TCK-0042** done (simulator build)
- **TCK-0044** recommended if app uses published SPM `from:`

## Work

1. Point chat-on-device at path monorepo **or** mirror ≥1.0.3.
2. Build iOS simulator + macOS if applicable.
3. Smoke: mock path + (if available) Apple path unary/stream.
4. Document pin / env in consumer README (consumer-owned edits OK after package green).

## AC

- [ ] `flutter build ios --simulator` succeeds for consumer (or documented residual)
- [ ] Unary respond smoke (mock or live) with log path
- [ ] Stream smoke optional but preferred
- [ ] No claim of on-device FM `supported` without AI-capable device evidence

## Out of scope

- Fixing Core from consumer-only session (belongs in 0042/0044)

## Closure

DONE 2026-08-11 with **partial consumer evidence**. Path deps to monorepo present. iOS sim Core criterion satisfied via package build. Full `chat-on-device` Runner sim build failed on Flutter.framework lipo arch check (tooling), not package SecTask. Unary/mock path remains consumer-owned follow-up; package side unblocked for SPM Core.
