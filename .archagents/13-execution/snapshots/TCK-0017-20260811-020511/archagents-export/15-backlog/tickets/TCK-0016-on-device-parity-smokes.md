---
id: TCK-0016
slug: on-device-parity-smokes
title: "On-device Apple Intelligence smokes + parity supported cells"
source: skeptic-gap-fix
created_at: 2026-08-10T23:55:00-03:00
status: blocked
priority: high
category: feature
effort: M
linked_spec: SPC-0001
related: [TCK-0004]
---

# TCK-0016 — On-device parity smokes

Follow-up for TCK-0004 residual. Measure on a real Apple Intelligence device:

1. unary respond Hello
2. stream + cancel (U1/U6)
3. Update docs/parity.md cells to `supported` with date/device/core version

Blocked by: physical device + Apple Intelligence enabled.

## Deferred (goal Non-goal / environment)

**Status: blocked — deferred residual of goal "full parity".** Requires Apple Silicon device + Apple Intelligence for on-device smokes (respond, stream, cancel). Until then `docs/parity.md` keeps Flutter cells as pure-Dart measured / not measured — never fake `supported`.

