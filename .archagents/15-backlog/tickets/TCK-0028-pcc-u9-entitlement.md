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
---

# TCK-0028 — PCC (U9)

## Gap

Parity **`blocked`** (same as upstream): requires `com.apple.developer.private-cloud-compute`.

## Work (when entitlement available)

1. Provision entitlement + profile.
2. Smoke availability/quota/respond for `apple.pcc`.
3. Promote cell only with measured path; keep no silent cloud elsewhere.

## AC

- [ ] Stays `blocked` until entitlement + smoke
- [ ] Never mark `supported` without PCC entitlement evidence

## Closure

BLOCKED: PCC entitlement U9 required.
