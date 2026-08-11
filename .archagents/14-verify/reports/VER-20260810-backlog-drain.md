---
ver_id: VER-20260810-backlog-drain
run_id: RUN-20260810-backlog-drain
status: approved-with-explicit-residuals
---

# VER-20260810-backlog-drain

## Verification plan results

| # | Check | Result |
|---|-------|--------|
| 1 | Dual pure-Dart tests + analyze | **pass** — platform_interface 54×2, foundationmodels 83×2, all phase packages green; analyze fatal-infos clean |
| 2 | Backlog terminal | **pass with residuals** — original non-epics done except TCK-0004 **blocked** (device); epics done; TCK-0016/0017 explicit deferred residuals |
| 3 | Protocol surface | **pass** — protocol_surface_test + tools_e2e_test (wire tools, stream-only, duplex) |
| 4 | Parity honesty | **pass** — zero Flutter `supported` cells; tools pure-Dart measured |
| 5 | Apple compile | **pass** — ios-bridge U1–U8 `swift build` complete |
| 6 | On-device | residual TCK-0004/0016 blocked+deferred |
| 7 | CI | **pass** — `.github/workflows/dart.yml` + `apple.yml` |

## Skeptic tools gaps (re-audit)

| Gap | Status |
|-----|--------|
| FmRequest.tools + respond/stream APIs | **fixed** — runtime.dart / session.dart |
| TransportProvider wire tools | **fixed** — _requestParams emits tools |
| Stream-only callback enforce | **fixed** — ToolCallbacksRequireStreamingException |
| Mock tools:true + duplex | **fixed** — mock_provider.dart + tools_e2e_test.dart |

Evidence: `{SCRATCH}/surface-tools.log`, `surface-tools-structural.log`, `dart-tests.log`.

## Explicit residuals (not silent)

1. **TCK-0004 / TCK-0016** blocked — device smokes
2. **TCK-0017** open — publish foundationmodels-swift
3. Phase 7 MCP client — deferred (documented CONTINUATION §9)
