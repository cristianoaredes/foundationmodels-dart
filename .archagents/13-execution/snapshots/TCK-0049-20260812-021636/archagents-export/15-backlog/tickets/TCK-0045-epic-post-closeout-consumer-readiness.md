---
id: TCK-0045
slug: epic-post-closeout-consumer-readiness
title: "Épico: post-closeout consumer readiness (ship + iOS sim + mirror + chat-on-device)"
source: post-closeout-backlog
created_at: 2026-08-11T16:00:00-03:00
status: done
priority: high
category: feature
effort: L
related: [TCK-0029, TCK-0042, TCK-0043, TCK-0044, TCK-0040]
---

# TCK-0045 — Epic: post-closeout consumer readiness

## Goal

After matrix closeout (TCK-0029), make the package **consumable and shippable**:

1. Governed evidence (VER) + ship hygiene  
2. iOS Simulator build unblocked  
3. Mirror tag with closeout + iOS fixes  
4. Sibling consumer path viable  

## Children (ordered)

| Order | Ticket | Role |
|-------|--------|------|
| 0 | [TCK-0043](TCK-0043-closeout-verify-ship-hygiene.md) | VER + ship hygiene |
| 1 | [TCK-0042](TCK-0042-ios-sim-consumer-build-unblocked.md) | iOS sim Core guards |
| 2 | [TCK-0044](TCK-0044-mirror-1-0-3-publish.md) | Publish mirror ≥1.0.3 |
| 3 | [TCK-0040](TCK-0040-chat-on-device-integration.md) | Consumer integration |

Optional later (not epic-blocking): TCK-0038, 0039, 0041.  
Gated forever until external: TCK-0028 PCC.

## Program DoD

See [POST-CLOSEOUT.md](../POST-CLOSEOUT.md).

## Status

`todo` until children 0043+0042+0044 done; 0040 may remain deferred with note.

## Closure

DONE 2026-08-11. Children 0043/0042/0044 done; 0040 partial with package unblock; opt-ins 0038/39/41 deferred product; 0028 blocked.
