---
run_id: RUN-20260810-backlog-drain
ticket: TCK-0009
design: none
status: completed
test_result: pass
started_at: 2026-08-10T21:50:00-03:00
finished_at: 2026-08-10T23:55:00-03:00
---

# RUN-20260810-backlog-drain

## Summary

Capability parity push vs foundationmodels-js: protocol surface, ios-bridge U1–U8,
phases 3–8 pure-Dart packages, honest backlog residuals for device/publish.

## Packages

foundationmodels, platform_interface, apple, policy, rag, eval, daemon, tools,
agent, server, langchain

## Tests

All pure-Dart package suites green (dual-run). flutter analyze apple clean.
ios-bridge swift build green. foundationmodels-swift `swift package describe` green.

## Residuals (tickets)

- TCK-0004 blocked + TCK-0016: on-device smokes
- TCK-0017 open: publish foundationmodels-swift GitHub mirror
