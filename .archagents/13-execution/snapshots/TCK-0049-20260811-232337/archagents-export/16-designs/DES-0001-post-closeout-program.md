---
id: DES-0001
title: Post-closeout consumer readiness program
ticket: TCK-0045
created_at: 2026-08-11
status: approved-for-L2
---

# DES-0001 — Post-closeout program

## Problem

Matrix closeout (TCK-0029) is **locally true** but:

1. Not adversarially verified (no VER-closeout).  
2. Not fully materialised for consumers (git / mirror `1.0.2`).  
3. iOS Simulator consumers blocked (FND-0009).  

## Alternatives considered

| Option | Pros | Cons |
|--------|------|------|
| A. Only document limits | Cheap | Consumer still broken on iOS sim |
| B. Fix Core iOS guards + ship mirror | Unblocks all Flutter iOS consumers | Needs Core care + publish |
| C. Consumer-only fork of Core | Fast for one app | Diverges; operator rejected |

**Decision:** **B** via ordered tickets 0043 → 0042 → 0044 → 0040.

## Architecture impact

- Core: platform-conditional PCC probe + vision tools (fail-closed on iOS).  
- Mirror: new semver including duplex (already in monorepo) + guards.  
- Plugin docs: path layout contract only (no absolute paths).  
- No change to Dart public API surface required for 0042.

## Risks

| Risk | Mitigation |
|------|------------|
| Break macOS host smokes | Re-run duplex / pure-Dart after Core edit |
| Publish wrong tree | TCK-0044 checklist; human gate on tag push |
| Soft-pass iOS FM | Explicit: sim build ≠ generation supported |

## Playbooks

- [PB-POST-CLOSEOUT-0042-ios-sim.md](playbooks/PB-POST-CLOSEOUT-0042-ios-sim.md)

## Approval

L2: design recorded; execute children without re-design unless AC changes.
