---
id: TCK-0050
slug: coreai-content-when-registered
title: "CoreAI — content dual-run on monorepo tip when model registered"
source: next-wave-intake
created_at: 2026-08-11T21:00:00-03:00
status: todo
priority: high
category: feature
effort: L
related: [TCK-0054, TCK-0046, TCK-0034, TCK-0022, TCK-0047]
program: STAGE-1
stage: 1
order: 2
wave: stage1
executable_now: true
unblock_when: "Probe always executable; content dual-run needs monorepo+model"
supersedes_limit_of: TCK-0034
---

# TCK-0050 — CoreAI content path (Stage 1 #2)

## Gap

TCK-0034 closed as permanent limit on **distribution mirror** (CoreAI stubbed). Stage 1: measure **monorepo** content path or reaffirm env limit with evidence.

## Status note

Promoted `blocked` → **`todo`**: monorepo probe always runnable; content still gated on model/OS.

## Phases

### 2a Probe (always)

```bash
export FOUNDATIONMODELS_SWIFT_PATH=/path/to/foundationmodels-js/swift
# Build plugin or host-native smoke that resolves Core packages
# Expect: either resolve OK or typed CoreAILanguageModels / missing module log
```

Respect TCK-0047 path contract (never Core alone).

### 2b Content dual-run (if probe + model ok)

1. Availability lists CoreAI model id.  
2. Dual-run `respond` with explicit `model:`; no silent `apple.system` fallback.  
3. Optional stream.  

### 2c Honesty

- `docs/parity.md`: monorepo CoreAI vs mirror stub  
- CONTINUATION quirks if needed  

## AC

- [ ] Probe evidence (resolve ok or fail with reason)  
- [ ] Content dual-run **or** reaffirm blocked with date  
- [ ] Mirror default path still fail-closed / stub documented  
- [ ] No silent system fallback when CoreAI requested  

## Evidence template

```text
SMOKE coreai probe path=monorepo resolve_ok=true|false
SMOKE coreai dual_run_ok=true model=…   # if content
# OR
SMOKE coreai env_limit=true reason=… reaffirmed=YYYY-MM-DD
```

## Files likely to touch

- parity.md, CONTINUATION, smoke logs  
- upstream Core only if bugs found (external)  

## Out of scope

- Shipping CoreAI inside foundationmodels-swift mirror without deps  
- MLX (Stage 2)  
- MCP  

## Depends on

- TCK-0047 done (docs)  
- Prefer after TCK-0051 closed/reaffirmed (order), but probe can start anytime on Mac  
