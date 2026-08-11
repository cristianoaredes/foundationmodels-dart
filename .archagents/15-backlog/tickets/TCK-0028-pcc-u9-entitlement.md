---
id: TCK-0028
slug: pcc-u9-entitlement
title: "PCC inference — U9 entitlement gate (blocked)"
source: full-parity-backlog
created_at: 2026-08-11T04:00:00-03:00
status: blocked
priority: low
category: feature
effort: L
related: [TCK-0018, TCK-0046]
program: NEXT-WAVE
wave: C
executable_now: false
reaffirmed_at: 2026-08-11T20:00:00-03:00
playbook_ready_at: 2026-08-11T21:00:00-03:00
unblock_when: "com.apple.developer.private-cloud-compute entitlement + provisioning profile on team"
---

# TCK-0028 — PCC (U9)

## Gap

Parity **`blocked`** (same as upstream): requires `com.apple.developer.private-cloud-compute`.

## Unblock gate (all required)

1. Apple Developer team has PCC entitlement enabled.  
2. Provisioning profile + `.entitlements` include  
   `com.apple.developer.private-cloud-compute`.  
3. Host app / example / consumer signed with that profile.  
4. Operator confirms **no silent cloud** elsewhere remains true (PCC is explicit path only).

## Work (when entitlement available)

1. Add entitlement file / Xcode capability to the **host under test** (example or chat-on-device).  
2. Verify entitlement present at runtime if Core exposes probe (fail-closed if absent).  
3. Smoke matrix for `apple.pcc` (or documented model id):
   - availability / quota if exposed  
   - respond dual-run  
   - stream optional  
4. Ensure non-PCC paths never call PCC without request.  
5. Promote parity cell only with measured evidence; keep other cells unchanged.  
6. Document privacy/network implications for consumers (PCC is cloud by definition — **explicit**, not silent).

## AC

- [ ] Stays `blocked` until entitlement + smoke  
- [ ] Never mark `supported` without PCC entitlement evidence  
- [ ] Dual-run evidence when unblocked  
- [ ] No silent promotion of unrelated models to PCC  

## Playbook preflight (blocked state)

```bash
# Expect: no entitlement → PCC unavailable / typed error — OK while blocked
# Do not fake success.
```

## Evidence template (when unblocked)

```text
SMOKE pcc entitlement_present=true
SMOKE pcc run=1 availability_ok respond_ok
SMOKE pcc run=2 availability_ok respond_ok
SMOKE pcc dual_run_ok=true
```

## Files likely to touch

- Host entitlements / Xcode project  
- parity.md  
- optional Core/plugin only if bridge gaps  

## Out of scope

- Requesting entitlement from Apple on behalf of user without instruction  
- Enabling network for non-PCC features  

## Closure history

- **BLOCKED** residual-optin 2026-08-11 (reaffirmed).  
- **Playbook ready** next-wave 2026-08-11 — executable only after gate.
