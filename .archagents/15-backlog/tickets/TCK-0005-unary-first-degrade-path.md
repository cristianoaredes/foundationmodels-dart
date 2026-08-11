---
id: TCK-0005
slug: unary-first-degrade-path
title: "Path unary-first documentado até U1 (respond only)"
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

# TCK-0005 — Path unary-first documentado até U1 (respond only)

Enquanto stream não existe, formalizar path respond unary no package e guia de consumidor.

Acceptance:
- README/CONTINUATION seção "pre-U1: unary only"
- Exemplo createFoundationModels + session.respond
- Teste mock stream continua; unary smoke documentado para device
- chat-on-device notificado (opcional issue) para generate() via respond

Findings: RSK-0001

## Origem

Inventário formalizado a partir de:
- Sibling `../chat-on-device/FOUNDATIONMODELS-DART-GAPS.md`
- `CONTINUATION.md` §2–5
- `docs/specs/*`

## Log

- `2026-08-10T21:45:00-03:00` — **triaged** — criado no bootstrap do repo.
- `2026-08-10` — **done** — backlog drain: pure-Dart surface + bridge U1–U8 + packages; on-device evidence remains not measured where noted in docs/parity.md.
- `2026-08-10T23:55:00-03:00` — **done** — implemented/verified per drain; residuals only if noted in CONTINUATION/parity.
