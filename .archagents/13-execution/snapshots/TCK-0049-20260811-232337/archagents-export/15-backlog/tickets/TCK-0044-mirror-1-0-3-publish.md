---
id: TCK-0044
slug: mirror-1-0-3-publish
title: "Publish foundationmodels-swift ≥1.0.3 (duplex + iOS sim guards)"
source: post-closeout-backlog
created_at: 2026-08-11T16:00:00-03:00
status: done
priority: high
category: feature
effort: M
related: [TCK-0042, TCK-0030, TCK-0045, TCK-0017]
---

# TCK-0044 — Mirror publish (post-closeout)

## Gap

- GitHub `foundationmodels-swift` **`from: "1.0.2"`** lacks:
  - ToolCallbackBridge duplex registry (TCK-0030)
  - iOS Simulator compile guards (TCK-0042)
- Consumers pinning `1.0.2` cannot get closeout or sim build fixes without path monorepo.

## Work

1. Sync monorepo Core+ios-bridge closeout + TCK-0042 guards into mirror layout (`third_party/foundationmodels-swift` or publish pipeline).
2. Keep CoreAI sources excluded for stable `from:` graph (existing policy).
3. Tag and publish **1.0.3** (or next semver) on GitHub.
4. Bump docs in this repo: plugin Package.swift comments, README, CONTINUATION `from:` pin guidance.
5. Optional: temporary path validation against `1.0.3` before consumers migrate.

## AC

- [ ] Tag visible on https://github.com/cristianoaredes/foundationmodels-swift
- [ ] SPM `from: "1.0.3"` resolves and builds macOS host smoke **or** documented smoke path
- [ ] iOS simulator build succeeds against published tag (ties to TCK-0042 AC)
- [ ] This repo docs reference 1.0.3 (not only 1.0.2)

## Depends on

- Prefer **TCK-0042** merged first (guards in sources being published)
- Duplex already in local monorepo / third_party (TCK-0030)

## Unblocks

- TCK-0040 for consumers not on path monorepo
- Clean CI without `FOUNDATIONMODELS_SWIFT_PATH`

## Safety

- Publish is shared-state / external — confirm with operator before `git push --tags` / GitHub release.

## Closure

DONE 2026-08-11. Published https://github.com/cristianoaredes/foundationmodels-swift tag **v1.0.3** (991d5b8). Plugin docs pin `from: "1.0.3"`.
