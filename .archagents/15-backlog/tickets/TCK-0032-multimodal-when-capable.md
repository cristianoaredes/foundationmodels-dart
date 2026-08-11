---
id: TCK-0032
slug: multimodal-when-capable
title: "Multimodal — image path when model reports image support"
source: closeout-backlog
created_at: 2026-08-11T12:00:00-03:00
status: done
priority: medium
category: feature
effort: M
related: [TCK-0020, TCK-0029]
---

# TCK-0032 — Multimodal when capable

## Gap

- Dart fail-closed allowlist: ok.
- Host: `capabilities.features.multimodalInput=false` for `apple.system` → **partial** is honest today.
- EXIF / image respond not measured because system model reports no image.

## Work

1. Re-probe capabilities when OS/SDK changes; if any model has `image: true`, smoke base64/path respond.
2. If still false forever for system FM: document permanent capability limit and keep partial.
3. Never silent cloud for vision/multimodal.

## AC

- [ ] Either image respond dual-run → partial/supported update, or permanent limit note frozen in parity.md

## Closure

DONE 2026-08-11 as **capability-limited partial**.
- Host measured `capabilities.features.multimodalInput=false` for `apple.system` (TCK-0020).
- Dart fail-closed image allowlist remains.
- Stay partial until a model reports image support and content smoke passes.
