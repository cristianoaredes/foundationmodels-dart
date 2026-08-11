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
reaffirmed_at: 2026-08-11T20:00:00-03:00
run: RUN-20260811-residual-optin
---

# TCK-0028 — PCC (U9)

## Gap

Parity **`blocked`** (same as upstream): requires `com.apple.developer.private-cloud-compute`.

## Work (when entitlement available)

1. Provision entitlement + profile.
2. Smoke availability/quota/respond for `apple.pcc`.
3. Promote cell only with measured path; keep no silent cloud elsewhere.

## AC

- [x] Stays `blocked` until entitlement + smoke
- [x] Never mark `supported` without PCC entitlement evidence

## Closure

**BLOCKED** (reaffirmed **2026-08-11** during residual-optin L3 drain):

- No PCC entitlement / provisioning profile available on this team/machine.
- Parity cell remains `blocked`; no silent cloud path.
- Residual opt-in drain (TCK-0038/39/41) does **not** unblock PCC.

Unblock only when entitlement is provisioned + host smoke evidence exists.
