---
id: TCK-0050
slug: coreai-content-when-registered
title: "CoreAI — content dual-run on monorepo tip when model registered"
source: next-wave-intake
created_at: 2026-08-11T21:00:00-03:00
status: blocked
priority: medium
category: feature
effort: L
related: [TCK-0046, TCK-0034, TCK-0022, TCK-0047]
program: NEXT-WAVE
order: 5
wave: B
executable_now: false
unblock_when: "FOUNDATIONMODELS_SWIFT_PATH=monorepo swift/ + CoreAI model registered; mirror stays stubbed"
supersedes_limit_of: TCK-0034
---

# TCK-0050 — CoreAI content path (when registered)

## Gap

TCK-0034 closed as permanent limit on **distribution mirror** (CoreAI stubbed). Content not measured. Reopen only via **monorepo tip**, never by silently enabling CoreAI in mirror `from:` graph without deps.

## Unblock gate

1. `FOUNDATIONMODELS_SWIFT_PATH` → monorepo `foundationmodels-js/swift` with CoreAI packages resolving.  
2. CoreAI model registered / OS provides backend.  
3. TCK-0047 docs contract understood (do not point path at Core alone).

## Depends on

- Monorepo checkout + CoreAI modules  
- Prefer after TCK-0047 (docs)  

## Work (when unblocked)

1. Build plugin/host with monorepo path (Mac).  
2. Dual-run availability + respond with `apple.coreai:*` (or real id).  
3. Confirm mirror default path still fail-closed without monorepo.  
4. Label all evidence **monorepo-only**; do not claim mirror SPM supports CoreAI.  
5. Update parity.md with split: mirror vs monorepo columns if needed.

## AC

- [ ] Dual-run content on monorepo path  
- [ ] Mirror path remains fail-closed / stub documented  
- [ ] No silent `apple.system` fallback when CoreAI requested  
- [ ] Or: reaffirm blocked with date  

## Evidence template

```text
SMOKE coreai path=monorepo run=1 respond_ok
SMOKE coreai path=monorepo run=2 respond_ok
SMOKE coreai mirror_stub_ok=true
```

## Files likely to touch

- parity.md, CONTINUATION, smoke logs  
- Upstream Core if bugs found (external ticket)  

## Out of scope

- Shipping CoreAI inside foundationmodels-swift mirror without full dep graph  
