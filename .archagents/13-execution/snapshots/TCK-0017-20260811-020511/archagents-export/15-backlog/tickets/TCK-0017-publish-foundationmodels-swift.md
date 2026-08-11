---
id: TCK-0017
slug: publish-foundationmodels-swift
title: "Publish foundationmodels-swift GitHub mirror (vendored sources)"
source: skeptic-gap-fix
created_at: 2026-08-10T23:55:00-03:00
status: open
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

