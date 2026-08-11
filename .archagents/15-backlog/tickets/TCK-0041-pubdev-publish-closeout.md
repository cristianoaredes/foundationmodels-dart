---
id: TCK-0041
slug: pubdev-publish-closeout
title: "Optional — pub.dev publish / remove publish_to none"
source: closeout-backlog-adjacent
created_at: 2026-08-11T12:00:00-03:00
status: done
priority: low
category: feature
effort: M
related: [TCK-0045, FND-0007, FND-0008, ADR-0002]
program: POST-CLOSEOUT
order: 99
done_at: 2026-08-11T20:00:00-03:00
run: RUN-20260811-residual-optin
---

# TCK-0041 — pub.dev closeout (adjacent)

## Work

1. License/docs/versioning gate for **AGPL-3.0-only** packages (FND-0008).
2. Decide per package: remove `publish_to: none` **or** ADR “stay private / git-only”.
3. `dart pub publish --dry-run` green for packages intended public.

## AC

- [x] Dry-run green for intended packages **or** explicit ADR stay-private
- [x] No accidental publish of internal-only packages

## Safety

- Real `dart pub publish` = shared external state → **human confirmation** (not L2/L3 alone).

## Closure (2026-08-11)

**done** via **ADR-0002 stay-private / git-only**:

1. Dry-run executed (not green — expected):
   - `foundationmodels`: missing package LICENSE, path dep on platform_interface
   - `foundationmodels_agent`: LICENSE + path deps on foundationmodels/tools
2. All workspace packages keep `publish_to: none`.
3. Distribution remains git monorepo + SPM mirror.
4. **No** real publish performed.

**ADR:** `.archagents/09-decisions/ADR-0002-stay-private-git-only.md`  
**Evidence:** `RUN-20260811-residual-optin/evidence/pub-dry-run-*.log`
