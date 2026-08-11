---
id: TCK-0025
slug: sessions-ttl-lru
title: "Sessions TTL 30m / LRU 256 — observe or document Core-owned"
source: full-parity-backlog
created_at: 2026-08-11T04:00:00-03:00
status: done
priority: low
category: feature
effort: M
related: [TCK-0014, TCK-0018]
---

# TCK-0025 — Session TTL / LRU honesty

## Gap

Sessions row is `supported` for transition/prewarm/materialization; **TTL 30 min / LRU 256 not observed**.

## Work

1. Determine ownership: Core SessionRegistry vs Dart lazy ids.
2. If Core-owned: document + optional long-running smoke or unit-level registry test in monorepo; do not fake Flutter measurement.
3. If Dart-owned: implement + test eviction semantics.
4. Update parity notes accordingly.

## AC

- [ ] Notes in parity.md no longer claim unmeasured TTL/LRU as fully covered
- [ ] Measurement **or** explicit "Core-owned / not Flutter-owned" note

## Closure

DONE 2026-08-11: Core SessionRegistry TTL 30m / LRU 256 documented.
