# pub.dev prep checklist (TCK-0052 Phase 1)

**Date:** 2026-08-11  
**ADR:** [ADR-0002](../09-decisions/ADR-0002-stay-private-git-only.md) — stay-private until Phase 2 human gate  
**Evidence:** `RUN-20260811-wave-a/evidence/pub-dry-run-*.log`

## Package inventory

| Package | Intent | LICENSE | CHANGELOG | repository | dry-run errors | publish_to |
|---------|--------|---------|-----------|------------|----------------|------------|
| **foundationmodels_platform_interface** | public candidate | ✅ | ✅ | ✅ | **0** (git dirty warn only) | none |
| **foundationmodels** | public candidate | ✅ | ✅ | ✅ | path dep on platform_interface | none |
| **foundationmodels_apple** | public later | ✅ | ✅ | ✅ | path dep on platform_interface | none |
| foundationmodels_tools | private / later | — | — | — | not prepped | none |
| foundationmodels_agent | private / later | — | — | — | not prepped | none |
| foundationmodels_daemon | private | — | — | — | not prepped | none |
| foundationmodels_eval | private | — | — | — | not prepped | none |
| foundationmodels_rag | private | — | — | — | not prepped | none |
| foundationmodels_policy | private | — | — | — | not prepped | none |
| foundationmodels_server | private | — | — | — | not prepped | none |
| foundationmodels_langchain | private | — | — | — | not prepped | none |

## AGPL (FND-0008)

All packages under monorepo **AGPL-3.0-only**. Publishing to pub.dev propagates AGPL obligations to network-use consumers. Call out in package README before Phase 2.

## Residual before dry-run zero-errors on `foundationmodels`

1. Publish **platform_interface** first (or use same-version hosted dep).  
2. Temporarily replace path deps with hosted versions for publish commit only.  
3. Clean git tree.  
4. Keep `publish_to: none` until human Phase 2.

## Phase 2 (human only)

- Explicit approval in RUN  
- Remove `publish_to: none` per package  
- `dart pub publish` (not dry-run)  
- Pin consumers to hosted versions  
