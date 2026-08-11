---
id: TCK-0047
slug: fnd-0010-path-contract-docs
title: "Docs — FOUNDATIONMODELS_SWIFT_PATH monorepo vs mirror contract (FND-0010)"
source: next-wave-intake
created_at: 2026-08-11T21:00:00-03:00
status: todo
priority: high
category: chore
effort: S
related: [TCK-0046, TCK-0042, FND-0010]
program: NEXT-WAVE
order: 1
wave: A
executable_now: true
---

# TCK-0047 — Path contract docs (FND-0010)

## Gap

Consumers pointing `FOUNDATIONMODELS_SWIFT_PATH` at monorepo Core **without** full monorepo Package graph pull CoreAI sources → compile fails (`CoreAILanguageModels` missing). Mirror excludes CoreAI by design. Docs are partial; FND-0010 still **open**.

## Depends on

- None (executable now). Mirror pin `from: "1.0.4"` already published.

## Work

1. Audit current wording in:
   - `packages/foundationmodels_apple/README.md`
   - `CONTINUATION.md` § quirks / validate
   - iOS/macOS `Package.swift` comments (if any)
2. Add explicit **decision table**:
   | Intent | Set env? | Path shape | CoreAI |
   |--------|----------|------------|--------|
   | CI / consumers / iOS sim | unset | GitHub `from: "1.0.4"` | stub/excluded |
   | Full Apple tip on Mac | set | monorepo `foundationmodels-js/swift` | full deps |
   | **Forbidden** | set | monorepo Core package alone | breaks |
3. Document recovery: unset env → mirror pin; or point at full monorepo root `swift/`.
4. Close **FND-0010** in `findings.md` with evidence paths.
5. Optional: one-line note in `example/` or plugin if present.

## AC

- [ ] Decision table present in plugin README (or linked single source)
- [ ] CONTINUATION § validate matches table
- [ ] FND-0010 status → closed with ticket ref
- [ ] No behavior change required (docs-only OK); if code comments updated, no API change

## Evidence template

```text
# After change
rg -n "FOUNDATIONMODELS_SWIFT_PATH|1\\.0\\.4|CoreAI" packages/foundationmodels_apple/README.md CONTINUATION.md
# findings.md FND-0010 closed
```

## Files likely to touch

- `packages/foundationmodels_apple/README.md`
- `CONTINUATION.md`
- `.archagents/11-assessment/findings.md`
- optionally `Package.swift` header comments

## Out of scope

- Implementing CoreAI in the mirror  
- Changing default pin without release  

## Risks

Low. Doc drift only — keep P7 sync.
