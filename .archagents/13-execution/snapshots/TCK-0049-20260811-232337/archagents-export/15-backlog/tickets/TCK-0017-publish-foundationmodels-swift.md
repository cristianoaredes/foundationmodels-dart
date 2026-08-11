---
id: TCK-0017
slug: publish-foundationmodels-swift
title: "Publish foundationmodels-swift GitHub mirror (vendored sources)"
source: skeptic-gap-fix
created_at: 2026-08-10T23:55:00-03:00
status: done
priority: medium
category: feature
effort: M
related: [TCK-0015]
---

# TCK-0017 — Publish foundationmodels-swift

TCK-0015 delivered a local path-based umbrella that resolves monorepo Core+Bridge.
This ticket covers publishing real sources to github.com/cristianoaredes/foundationmodels-swift
(subtree-split/vendor + tags) so remote SPM URL works without FOUNDATIONMODELS_SWIFT_PATH.

## Deferred (goal Non-goal / publish)

**Status: open — deferred residual.** Local path-based `third_party/foundationmodels-swift` umbrella resolves monorepo Core+Bridge when `FOUNDATIONMODELS_SWIFT_PATH` is set. Publishing vendored sources to GitHub is out of this machine's credential scope; track separately. Local compile path via monorepo is the supported distribution for development.
- `2026-08-11T02:20:00-03:00` — **done** — published https://github.com/cristianoaredes/foundationmodels-swift tag v1.0.0 (vendored Core+Bridge SPM package).
- `2026-08-11` — **done (SPM-stable)** — v1.0.2 drops coreai-models/xgrammar@main; remote `from: "1.0.2"` resolve+build+run proven (mirror-resolve.log CONSUMER_RESOLVE_OK).
