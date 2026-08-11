---
id: TCK-0020
slug: multimodal-native-path
title: "Multimodal — native image path + EXIF honesty"
source: full-parity-backlog
created_at: 2026-08-11T04:00:00-03:00
status: done
priority: medium
category: feature
effort: L
related: [TCK-0010, TCK-0018]
---

# TCK-0020 — Multimodal native path

## Gap

Flutter **`partial`**: Dart fail-closed `allowedImageRoots` only. Host reports `multimodalInput=false` / `apple.system.supports.image=false`. EXIF native not measured.

## Work

1. Confirm Apple FM / Core route for image parts on available models (system vs PCC vs MLX-VLM).
2. If system model never supports images: keep **`partial`** with explicit capability-gate evidence (not a bug).
3. If a model supports images: host smoke path/base64 + label; document EXIF behavior or measured strip.
4. Never silent cloud for vision.

## AC

- [ ] Matrix cell is `supported` with smoke **or** remains `partial` with capability-limit note + evidence log

## Closure

DONE 2026-08-11: multimodalInput=false honesty; cell remains partial.
