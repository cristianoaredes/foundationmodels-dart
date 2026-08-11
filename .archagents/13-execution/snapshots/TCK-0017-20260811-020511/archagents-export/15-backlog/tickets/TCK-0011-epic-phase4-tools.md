---
id: TCK-0011
slug: epic-phase4-tools
title: "Épico: Phase 4 tool calling (U7)"
source: bootstrap+gaps-inventory
created_at: 2026-08-10T21:45:00-03:00
created_by: codebase-ops bootstrap (chat-on-device handoff)
updated_at: 2026-08-10T21:45:00-03:00
status: done
severity: medium
category: feature
effort: L
flow: normal
ceremony: full
linked_spec: SPC-0001
linked_findings: []
related: [TCK-0009]
---

# TCK-0011 — Épico: Phase 4 tool calling (U7)

Placeholder — phase-4-tools.md

## Origem

Inventário formalizado a partir de:
- Sibling `../chat-on-device/FOUNDATIONMODELS-DART-GAPS.md`
- `CONTINUATION.md` §2–5
- `docs/specs/*`

## Log

- `2026-08-10T21:45:00-03:00` — **epic** — criado no bootstrap do repo.
- `2026-08-10` — **done** — backlog drain: pure-Dart surface + bridge U1–U8 + packages; on-device evidence remains not measured where noted in docs/parity.md.
- `2026-08-10T23:55:00-03:00` — **done** — implemented/verified per drain; residuals only if noted in CONTINUATION/parity.
- `2026-08-10` — **done (real path)** — FmRequest.tools + respond/stream APIs + TransportProvider wire `tools` + mock duplex + stream-only enforcement; tests in tools_e2e_test.dart.
