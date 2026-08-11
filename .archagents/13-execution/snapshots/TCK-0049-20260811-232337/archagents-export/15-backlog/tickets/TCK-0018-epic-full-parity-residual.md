---
id: TCK-0018
slug: epic-full-parity-residual
title: "Épico: full parity residual (honest matrix close)"
source: full-parity-backlog
created_at: 2026-08-11T04:00:00-03:00
status: done
priority: high
category: feature
effort: L
linked_spec: SPC-0001
related: [TCK-0019, TCK-0020, TCK-0021, TCK-0022, TCK-0023, TCK-0024, TCK-0025, TCK-0026, TCK-0027, TCK-0028]
---

# TCK-0018 — Épico: full parity residual

## Definition of "full parity" (this program)

Close every upstream-`supported` Flutter row to either:

1. Flutter **`supported`** with host-native **or** iOS-device smoke evidence (date + device/OS + core/bridge), **or**
2. Explicit **`partial` / `not measured` / `blocked`** with a recorded product or environment limit — never silent overclaim.

**Out of definition:** line-by-line TS port; PCC without entitlement (stays `blocked`); inventing `supported` for pure-Dart-only packages.

## Baseline (2026-08-11)

Already `supported` (host-native Mac): availability, respond, stream+cancel, sessions (transition/prewarm), guided, countTokens, feedback, vision OCR.

Residual map → child tickets TCK-0019…0028.

## Acceptance

- [ ] All child TCKs done or explicitly deferred with reason in ticket + `docs/parity.md`
- [ ] No Flutter `supported` without evidence-log line
- [ ] PCC still `blocked` unless U9 entitlement lands (TCK-0028)
- [ ] CONTINUATION + plan-board reflect residual status

## Closure

DONE 2026-08-11: all children closed; PCC remains blocked.
