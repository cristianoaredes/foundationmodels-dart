---
id: TCK-0052
slug: pubdev-prep-and-optional-publish
title: "pub.dev — package prep (and optional human-gated publish)"
source: next-wave-intake
created_at: 2026-08-11T21:00:00-03:00
status: todo
priority: medium
category: feature
effort: M
related: [TCK-0046, TCK-0041, ADR-0002, FND-0007, FND-0008]
program: NEXT-WAVE
order: 3
wave: A
executable_now: true
publish_requires_human: true
---

# TCK-0052 — pub.dev prep (+ optional publish)

## Gap

ADR-0002 keeps **stay-private / git-only**. Dry-run fails: no per-package LICENSE, path deps, missing homepage/CHANGELOG. If product ever wants pub.dev, prep must be done first without accidental publish.

## Two phases

### Phase 1 — Prep (executable now, L2/L3 OK)

1. Inventory packages intended public vs internal-only:
   - **Candidates public:** `foundationmodels`, `foundationmodels_platform_interface` (maybe apple later)  
   - **Likely private forever:** daemon, server, eval, rag, agent experiments — confirm per product  
2. For each **candidate**:
   - LICENSE (AGPL-3.0-only copy or root policy)  
   - CHANGELOG.md  
   - `repository` / `homepage` in pubspec  
   - Replace path deps with versioned workspace / hosted strategy (document if still path until first publish)  
3. `dart pub publish --dry-run` green **or** documented remaining blockers.  
4. Keep `publish_to: none` until Phase 2.  
5. Update ADR-0002 with “prep status” note or ADR-0003 “reopen publish” if going public.

### Phase 2 — Publish (human SAFETY only)

1. Explicit operator approval.  
2. Remove `publish_to: none` per package.  
3. `dart pub publish` (not dry-run).  
4. Pin consumers to hosted versions.

## AC

### Phase 1
- [ ] Checklist table package × (LICENSE, CHANGELOG, repository, dry-run status)  
- [ ] AGPL consumer implications noted (FND-0008)  
- [ ] `publish_to: none` still present until Phase 2  
- [ ] Dry-run improved vs residual-optin baseline (zero errors **or** listed residual)

### Phase 2 (optional)
- [ ] Human confirmation recorded in RUN  
- [ ] Published versions listed  
- [ ] No internal-only package published by mistake  

## Safety

- Real publish = **shared external state** → stop and confirm (any autonomy level).  
- Do not use `--force` to skip warnings without human.

## Evidence template

```text
# Phase 1
dart pub publish --dry-run  # per package; save logs under RUN evidence
```

## Files likely to touch

- `packages/*/LICENSE`, `CHANGELOG.md`, `pubspec.yaml`  
- `.archagents/09-decisions/ADR-0002…` or new ADR  
- root README distribution section  

## Out of scope

- Changing license to MIT/Apache without separate ADR  
