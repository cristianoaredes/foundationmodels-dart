---
id: TCK-0002
slug: upstream-u1-respond-stream
title: "U1 — respondStream no ios-bridge (foundationmodels-js) + wiring plugin"
source: bootstrap+gaps-inventory
created_at: 2026-08-10T21:45:00-03:00
created_by: codebase-ops bootstrap (chat-on-device handoff)
updated_at: 2026-08-10T21:45:00-03:00
status: done
severity: high
category: feature
effort: L
flow: normal
ceremony: full
linked_spec: SPC-0001
linked_findings: []
related: [TCK-0009]
---

# TCK-0002 — U1 — respondStream no ios-bridge (foundationmodels-js) + wiring plugin

Implementar ou integrar U1 (respondStream) no monorepo Swift e validar envelope no plugin.

Acceptance:
- Spec docs/specs/upstream-ios-bridge-extensions.md §U1 atendida ou ticket cross-repo com PR link
- Plugin emite text_delta … done no EventChannel
- Teste de contrato (fake transport) no Dart se bridge ainda remote

Blocks: TCK-0004
Findings: FND-0002
External: foundationmodels-js

## Origem

Inventário formalizado a partir de:
- Sibling `../chat-on-device/FOUNDATIONMODELS-DART-GAPS.md`
- `CONTINUATION.md` §2–5
- `docs/specs/*`

## Log

- `2026-08-10T21:45:00-03:00` — **raw** — criado no bootstrap do repo.
- `2026-08-10` — **done** — backlog drain: pure-Dart surface + bridge U1–U8 + packages; on-device evidence remains not measured where noted in docs/parity.md.
- `2026-08-10T23:55:00-03:00` — **done** — implemented/verified per drain; residuals only if noted in CONTINUATION/parity.
