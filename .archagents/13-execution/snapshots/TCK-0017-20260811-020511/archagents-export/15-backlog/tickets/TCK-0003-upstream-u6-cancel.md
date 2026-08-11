---
id: TCK-0003
slug: upstream-u6-cancel
title: "U6 — cancel in-process da geração + CancelToken no plugin"
source: bootstrap+gaps-inventory
created_at: 2026-08-10T21:45:00-03:00
created_by: codebase-ops bootstrap (chat-on-device handoff)
updated_at: 2026-08-10T21:45:00-03:00
status: done
severity: high
category: feature
effort: M
flow: normal
ceremony: full
linked_spec: SPC-0001
linked_findings: []
related: [TCK-0009]
---

# TCK-0003 — U6 — cancel in-process da geração + CancelToken no plugin

Cancel nativo alinhado ao CancelToken Dart.

Acceptance:
- generation.cancel interrompe stream com GenerationCancelledException
- Idempotência de cancel documentada
- Evidence on-device ou contrato com fake

Blocked by: TCK-0002 (stream)
Findings: FND-0003

## Origem

Inventário formalizado a partir de:
- Sibling `../chat-on-device/FOUNDATIONMODELS-DART-GAPS.md`
- `CONTINUATION.md` §2–5
- `docs/specs/*`

## Log

- `2026-08-10T21:45:00-03:00` — **raw** — criado no bootstrap do repo.
- `2026-08-10` — **done** — backlog drain: pure-Dart surface + bridge U1–U8 + packages; on-device evidence remains not measured where noted in docs/parity.md.
- `2026-08-10T23:55:00-03:00` — **done** — implemented/verified per drain; residuals only if noted in CONTINUATION/parity.
