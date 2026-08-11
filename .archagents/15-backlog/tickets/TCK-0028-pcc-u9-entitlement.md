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
related: [TCK-0018]
program: OPEN-BACKLOG
repo_only: true
reaffirmed_at: 2026-08-11T24:00:00-03:00
executable_now: false
unblock_when: "com.apple.developer.private-cloud-compute + provisioning profile"
---

# TCK-0028 — PCC (U9)

## Gap

Parity **blocked** until Apple PCC entitlement.

## When unblocked (this repo / host under test)

1. Entitlements on example or test host.  
2. Smoke availability/respond for PCC model id.  
3. Promote parity cell only with evidence; no silent cloud elsewhere.  

## AC

- [x] Stays blocked until entitlement  
- [x] Never mark `supported` without evidence  
- [ ] Dual-run when unblocked  

## Out of scope

- Requesting entitlement from Apple without operator instruction  
