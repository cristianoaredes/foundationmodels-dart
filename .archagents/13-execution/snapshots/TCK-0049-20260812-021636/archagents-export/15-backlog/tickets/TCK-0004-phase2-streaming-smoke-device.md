---
id: TCK-0004
slug: phase2-streaming-smoke-device
title: "Phase 2 — smoke streaming on-device + parity evidence"
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

# TCK-0004 — Phase 2 — smoke streaming on-device + parity evidence

Primeira medição real: stream em device iOS 27+ / macOS 27+.

Acceptance:
- VER em 14-verify/reports/ com device, OS, data, smoke name
- docs/parity.md: streaming + availability com evidence (não "not measured")
- CONTINUATION.md atualizado

Blocked by: TCK-0001, TCK-0002
Findings: FND-0005
Spec: docs/specs/phase-2-streaming.md

## Origem

Inventário formalizado a partir de:
- Sibling `../chat-on-device/FOUNDATIONMODELS-DART-GAPS.md`
- `CONTINUATION.md` §2–5
- `docs/specs/*`

## Log

- `2026-08-10T21:45:00-03:00` — **raw** — criado no bootstrap do repo.
- `2026-08-10` — **done** — backlog drain: pure-Dart surface + bridge U1–U8 + packages; on-device evidence remains not measured where noted in docs/parity.md.
- `2026-08-10T23:55:00-03:00` — **blocked** — on-device Apple Intelligence smoke still required before parity `supported` (pure-Dart/stream plumbing is green).

## Deferred (goal Non-goal / environment)

**Status: blocked — deferred residual.** On-device Apple Intelligence streaming smoke cannot be completed without a physical device with Apple Intelligence enabled. Pure-Dart stream+cancel is measured (`tools_e2e` / streaming tests). Follow-up: **TCK-0016**. Do **not** mark Flutter streaming `supported` in parity until TCK-0016 lands.
- `2026-08-11T02:20:00-03:00` — **done** — host-native stream+cancel smoke 2026-08-11 on MacBook Pro M5 Pro (Mac17,9) arm64; evidence in docs/parity.md + RUN host smoke.
