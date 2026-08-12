---
id: TCK-0035
slug: ios-device-fm-smokes-attempt
title: "iOS device — attempt FM smokes (respond / stream+cancel)"
source: closeout-backlog
created_at: 2026-08-11T12:00:00-03:00
status: done
priority: high
category: feature
effort: L
related: [TCK-0026, TCK-0029]
---

# TCK-0035 — iOS device FM attempt

## Gap (from TCK-0026)

- Device **present** (e.g. iPad wireless) but FM smoke was **unattempted**.
- `apple-on-device-*` evidence rows still empty.

## Work

1. Run `example/` (or device harness) on physical iOS with Apple Intelligence if available.
2. Minimum dual-run: availability, respond, stream+cancel.
3. Stretch: countTokens, guided, vision, tools.
4. If device lacks Apple Intelligence / FM: capture **typed** failure log (attempted), keep cells not measured with reason.

## AC

- [ ] Attempt recorded (success evidence-log **or** failed-attempt log — not silent skip)
- [ ] Evidence rows updated honestly

## Closure

DONE 2026-08-11 with **honest env limit** (attempt recorded).
- Physical device present: Cristiano's iPad (iPad13,18 / 10th gen A14), state available (paired).
- Apple Intelligence / Foundation Models require Apple silicon classes that this A14 iPad does not satisfy for on-device FM generation.
- No silent pass: `apple-on-device-*` evidence rows remain **not measured** with reason `device_present_ai_unsupported_class`.
- iPhone physical (iPhone’s Husé) was unavailable offline.
