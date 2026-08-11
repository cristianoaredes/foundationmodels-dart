---
id: TCK-0049
slug: mlx-content-when-weights
title: "MLX — content dual-run when model weights registered"
source: next-wave-intake
created_at: 2026-08-11T21:00:00-03:00
status: blocked
priority: medium
category: feature
effort: L
related: [TCK-0046, TCK-0033, TCK-0021]
program: NEXT-WAVE
order: 4
wave: B
executable_now: false
unblock_when: "MLX model weights registered via Core env / model root; apple.mlx:* not MODEL_NOT_FOUND"
supersedes_limit_of: TCK-0033
---

# TCK-0049 — MLX content path (when weights)

## Gap

TCK-0033 closed as **permanent product limit** (fail-closed `MODEL_NOT_FOUND` without weights). Content cell remains not measured. This ticket is the **reopen path** when weights exist.

## Unblock gate (all required)

1. Host has MLX model files and Core registry env (e.g. model root / `FOUNDATIONMODELS_*` as documented by Core).  
2. `availability` lists an `apple.mlx:*` (or documented id) without silent remap to `apple.system`.  
3. Operator confirms weights are licensed for local use.

## Depends on

- foundationmodels-js / Core MLX backend  
- Prefer monorepo `FOUNDATIONMODELS_SWIFT_PATH` for full tip  

## Work (when unblocked)

1. Document exact env vars + model path used (no secrets in repo).  
2. Dual-run (≥2):
   - health / availability includes MLX model id  
   - `respond` with explicit `model:` → non-empty text; usage/trace if available  
   - optional `stream` + cancel  
3. Assert **no silent fallback** to `apple.system` when MLX requested.  
4. Note unsupported options (tools/schema) if Core rejects.  
5. Update `docs/parity.md` cell only with measured evidence.  
6. Flutter path optional if host-native already proves Core; prefer both.

## AC

- [ ] Dual-run content evidence with model id in request **and** response path  
- [ ] Fail-closed still holds for **unregistered** model ids  
- [ ] parity.md updated honestly (`supported` only if measured)  
- [ ] Or: gate still closed → reaffirm blocked with date + reason  

## Evidence template

```text
SMOKE mlx model=<id> run=1 availability_ok respond_ok
SMOKE mlx model=<id> run=2 availability_ok respond_ok
SMOKE mlx dual_run_ok=true no_system_fallback=true
```

## Files likely to touch

- Host smoke scripts / parity.md  
- Possibly plugin/docs only (Core lives upstream)  

## Out of scope

- Bundling large weights in this git repo  
- Claiming tools/schema on MLX without Core support  

## Playbook preflight

```bash
# Expect fail until gate open:
# availability / respond with model apple.mlx:… → MODEL_NOT_FOUND is OK while blocked
```
