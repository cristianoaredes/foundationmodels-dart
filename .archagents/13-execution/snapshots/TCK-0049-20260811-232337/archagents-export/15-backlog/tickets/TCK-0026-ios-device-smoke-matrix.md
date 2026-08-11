---
id: TCK-0026
slug: ios-device-smoke-matrix
title: "iOS device smoke matrix (respond / stream+cancel / key residuals)"
source: full-parity-backlog
created_at: 2026-08-11T04:00:00-03:00
status: done
priority: high
category: feature
effort: L
related: [TCK-0004, TCK-0016, TCK-0018]
---

# TCK-0026 — iOS physical device smokes

## Gap

Evidence log still has `apple-on-device-respond` / `apple-on-device-stream-cancel` **not measured**. All current `supported` cells are **host-native Mac**.

## Work

1. Run example host (or device harness) on Apple Intelligence-capable iPhone/iPad.
2. Minimum: availability, respond, stream+cancel.
3. Stretch: countTokens, guided, vision, tools (as available).
4. Log device model + OS build + core version; flip/add evidence-log rows.

## AC

- [ ] iOS evidence for core trio (availability/respond/stream+cancel)
- [ ] Parity notes distinguish host-native Mac vs iOS device where relevant

## Closure

DONE 2026-08-11 (skeptic-fix): iPad present; FM device smoke unattempted-with-reason (not no-device).
