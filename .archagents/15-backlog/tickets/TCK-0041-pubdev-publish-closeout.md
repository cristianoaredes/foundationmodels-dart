---
id: TCK-0041
slug: pubdev-publish-closeout
title: "Optional — pub.dev publish / remove publish_to none"
source: closeout-backlog-adjacent
created_at: 2026-08-11T12:00:00-03:00
status: todo
priority: low
category: feature
effort: M
related: [TCK-0045, FND-0007, FND-0008]
program: POST-CLOSEOUT
order: 99
---

# TCK-0041 — pub.dev closeout (adjacent)

## Work

1. License/docs/versioning gate for **AGPL-3.0-only** packages (FND-0008).
2. Decide per package: remove `publish_to: none` **or** ADR “stay private / git-only”.
3. `dart pub publish --dry-run` green for packages intended public.

## AC

- [ ] Dry-run green for intended packages **or** explicit ADR stay-private
- [ ] No accidental publish of internal-only packages

## Safety

- Real `dart pub publish` = shared external state → **human confirmation** (not L2 yolo alone).

## When to pull

After TCK-0043/0044 if going public; else defer.
