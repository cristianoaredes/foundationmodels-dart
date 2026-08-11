---
id: TCK-0008
slug: install-github-ci-workflows
title: "Instalar CI: docs/ci → .github/workflows"
source: bootstrap+gaps-inventory
created_at: 2026-08-10T21:45:00-03:00
created_by: codebase-ops bootstrap (chat-on-device handoff)
updated_at: 2026-08-10T21:45:00-03:00
status: done
severity: medium
category: feature
effort: S
flow: normal
ceremony: full
linked_spec: SPC-0001
linked_findings: []
related: [TCK-0009]
---

# TCK-0008 — Instalar CI: docs/ci → .github/workflows

Mover dart.yml (e apple.yml placeholder) para .github/workflows.

Acceptance:
- Push com token workflow scope ou instrução no runbook se bloqueado
- CI green no pure-Dart
Findings: FND-0004

## Origem

Inventário formalizado a partir de:
- Sibling `../chat-on-device/FOUNDATIONMODELS-DART-GAPS.md`
- `CONTINUATION.md` §2–5
- `docs/specs/*`

## Log

- `2026-08-10T21:45:00-03:00` — **triaged** — criado no bootstrap do repo.
- `2026-08-10` — **done** — backlog drain: pure-Dart surface + bridge U1–U8 + packages; on-device evidence remains not measured where noted in docs/parity.md.
- `2026-08-10T23:55:00-03:00` — **done** — implemented/verified per drain; residuals only if noted in CONTINUATION/parity.
