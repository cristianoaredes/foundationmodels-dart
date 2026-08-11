---
id: TCK-0006
slug: example-host-app
title: "Example host app mínimo (iOS/macOS) para smoke"
source: bootstrap+gaps-inventory
created_at: 2026-08-10T21:45:00-03:00
created_by: codebase-ops bootstrap (chat-on-device handoff)
updated_at: 2026-08-10T21:45:00-03:00
status: done
severity: medium
category: feature
effort: M
flow: normal
ceremony: full
linked_spec: SPC-0001
linked_findings: []
related: [TCK-0009]
---

# TCK-0006 — Example host app mínimo (iOS/macOS) para smoke

App de exemplo no monorepo ou packages/foundationmodels_apple/example para exercitar availability + respond/stream.

Acceptance:
- flutter create example ou example/ existente
- Botão availability + prompt one-shot
- Instruções no README

## Origem

Inventário formalizado a partir de:
- Sibling `../chat-on-device/FOUNDATIONMODELS-DART-GAPS.md`
- `CONTINUATION.md` §2–5
- `docs/specs/*`

## Log

- `2026-08-10T21:45:00-03:00` — **raw** — criado no bootstrap do repo.
- `2026-08-10` — **done** — backlog drain: pure-Dart surface + bridge U1–U8 + packages; on-device evidence remains not measured where noted in docs/parity.md.
- `2026-08-10T23:55:00-03:00` — **done** — implemented/verified per drain; residuals only if noted in CONTINUATION/parity.
