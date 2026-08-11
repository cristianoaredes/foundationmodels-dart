# Parity matrix — foundationmodels-dart vs. upstream

Mirrors the upstream
[`docs/parity.md`](https://github.com/cristianoaredes/foundationmodels-js)
capability rows, with a `Flutter status` column. Discipline inherited from
upstream: **never report a capability as supported unless it uses the native
Apple API or documents a precise fallback** — every `supported` cell requires
on-device evidence (smoke + date + device + core build) **or** an honest
pure-Dart measurement (mock/offline package) with evidence.

| Capability (upstream row) | Upstream status | Flutter status | Target phase | Notes |
|---|---|---|---|---|
| Availability (`availability` + reasonCodes) | supported | supported | 0 | Host-native smoke 2026-08-11; mock also measured |
| Text generation (`respond`) | supported | supported | 0 | Host-native unary smoke 2026-08-11; mock also measured |
| Streaming + cancel | supported | supported | 2 | Host-native dual-run cancel-on-first-delta → `["delta","error"]`, `stream_cancel_path_ok=true`, nonzero RC if miss |
| Sessions (lazy, TTL 30 min, LRU 256, `transition`, `prewarm`) | supported | supported | 3 | Host-native create/respond/transition/prewarm/dispose; **TTL/LRU are Core SessionRegistry defaults** (30m / 256, reap-on-access) — not reimplemented in Dart |
| Instructions (first-request-wins precedence) | supported | supported | 3 | Host dual-run (TCK-0031): underA=true + transitioned=true + **underB_clean=true** (create→transition→respond without prior chat). Post-history underB_hist may stay ALPHA (transcript dominance) — documented, not soft-pass |
| Guided generation (JSON Schema subset → `DynamicGenerationSchema`) | supported | supported | 3 | Host-native structured `output` object; Dart `FmSchema` fail-fast + mock extract/classify/rank |
| Multimodal (path/base64, allowlist, EXIF, `label`) | supported | partial (capability limit) | 3 | Fail-closed Dart `allowedImageRoots`; host `capabilities.features.multimodalInput=false` for `apple.system` (TCK-0020/0032 measured honesty) |
| `countTokens` / context overflow | supported | supported | 3 | Host-native measured tokens + `*Tokens` aliases on Dart |
| Feedback attachment | supported | supported | 3 | Host-native `attachmentBase64`; Dart prefers `sessionId` |
| Semantic index (local RAG) | supported | pure-Dart measured | 5 | `package:foundationmodels_rag` |
| Security / redaction | supported | pure-Dart measured | 3 | `package:foundationmodels_policy` |
| Eval harness + traces | supported | pure-Dart measured | 6 | `package:foundationmodels_eval` |
| MLX backend (`apple.mlx:*`) | supported | fail-closed (no weights) | 7 | Dual-run fail-closed `MODEL_NOT_FOUND` without registered weights (TCK-0021/0033); no silent system fallback |
| Tool calling (duplex + native + static) | supported | supported | 4 | Host dual-run duplex `DUPLEX-99` (TCK-0030) + static `PARITY-42`; Flutter live duplex dual-run (TCK-0036); registry timeout/retry/fail-closed |
| PCC inference | blocked (Apple entitlement) | blocked | gated (U9) | TCK-0028 remains blocked |
| CoreAI backend (`apple.coreai:*`) | supported | fail-closed (no registry / mirror stub) | 7 | Dual-run fail-closed `MODEL_NOT_FOUND`; mirror 1.0.2 stubs CoreAI (TCK-0022/0034) |
| Vision tools (OCR / barcode) | supported | supported | 3 | OCR text content; barcode dual-run `values=["PARITY-BARCODE-777"]` (TCK-0023) |
| Dynamic profiles / Spotlight tool | partial | pure-Dart measured (metadata only) | 3 | Upstream partial |

## Status legend

| Cell | Meaning |
|---|---|
| `supported` | On-device Apple path measured with smoke + date + device + core version |
| `pure-Dart measured` | Offline mock / pure-Dart package exercises the public API with tests; **not** a claim of on-device Apple support |
| `partial` | API or gate exists; full native path incomplete or capability-limited |
| `not measured` | Not yet content-smoke-tested (may include fail-closed probes) |
| `blocked` | Cannot support without external entitlement / dependency |

## Evidence log

| Smoke | Date | Surface | Device / OS | Core / notes |
|---|---|---|---|---|
| `pure-dart-protocol-surface` | 2026-08-10+ | full protocol via mock + TransportProvider envelopes | host | dual green in drain |
| `host-native-respond` | 2026-08-11 | availability + unary respond | Mac17,9 · macOS 27.0 (26A5388g) · Xcode 27 | monorepo Core |
| `host-native-stream-cancel` | 2026-08-11 | stream cancel-on-first-delta | same | `["delta","error"]` dual-run |
| `host-native-sessions` | 2026-08-11 | create/transition/prewarm/dispose | same | + TTL/LRU Core-owned note |
| `host-native-countTokens` | 2026-08-11 | countTokens measured | same | |
| `host-native-guided` | 2026-08-11 | json_schema structured | same | |
| `host-native-feedback` | 2026-08-11 | logFeedbackAttachment | same | |
| `host-native-vision-ocr` | 2026-08-11 | visionOcr texts | same | |
| `host-native-tools-static` | 2026-08-11 | static tool application | same | `PARITY-42` dual-run; toolTokens=80 |
| `host-native-tools-duplex` | 2026-08-11 | ToolCallbackBridge duplex | same | dual-run `tools_duplex_ok=true` content `DUPLEX-99` (TCK-0030) |
| `host-native-instructions` | 2026-08-11 | first-request-wins + transition | same | underA=true underB_clean=true underB_hist=false transitioned=true (TCK-0031) |
| `host-native-barcode` | 2026-08-11 | visionBarcode QR | same | `PARITY-BARCODE-777` dual-run |
| `host-native-multimodal-honesty` | 2026-08-11 | capabilities.multimodalInput | same | false for apple.system |
| `host-native-mlx-coreai-failclosed` | 2026-08-11 | unregistered model ids | same | MODEL_NOT_FOUND dual-run (TCK-0033/0034 permanent without registry) |
| `flutter-plugin-live-macos` | 2026-08-11 | public Dart API → channels → Core | Mac17,9 · macOS 27 · Xcode 27 | dual-run avail+respond+stream/cancel+tools duplex; `SMOKE_RC:0` (TCK-0036) |
| `foundationmodels-swift-v1.0.2` | 2026-08-11 | SPM mirror | GitHub | CoreAI stub |
| `apple-on-device-respond` | 2026-08-11 | iOS device attempt | iPad13,18 (A14) paired | **not measured** — device present; AI/FM unsupported class (TCK-0035) |
| `apple-on-device-stream-cancel` | 2026-08-11 | iOS device attempt | same | **not measured** — same limit |

> Host-native = Mac Apple Intelligence via FoundationModelsIOSBridge + FoundationModelsCore (monorepo).
> Do **not** invent `supported` without evidence. PCC stays `blocked`.
