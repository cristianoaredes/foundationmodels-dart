# Findings

| ID | Severity | Título | Status |
|----|----------|--------|--------|
| FND-0001 | high | `foundationmodels_apple` nunca compilado em Mac/device | **closed** (host + Flutter live 2026-08-11) |
| FND-0002 | high | Streaming depende de U1 (ios-bridge) inexistente no bridge atual | **closed** (U1 host + live E2E) |
| FND-0003 | high | Cancel nativo depende de U6 | **closed** (U6 measured) |
| FND-0004 | medium | CI workflows não estão em `.github/workflows/` | **closed** (workflows present) |
| FND-0005 | medium | Toda parity Flutter = `not measured` | **closed** (parity matrix closeout) |
| FND-0006 | medium | Mirror `foundationmodels-swift` não existe | **closed** (v1.0.2; next bump TCK-0044) |
| FND-0007 | low | `publish_to: none` — só consumo git | **closed** (ADR-0002 stay-private) |
| FND-0008 | info | AGPL-3.0-only no grafo de consumidores | open (policy awareness) |
| FND-0009 | high | iOS Simulator: consumer `chat-on-device` não builda com mirror `foundationmodels-swift` 1.0.2 (SecTask / OCRTool / graph SPM) | **closed** (v1.0.3 guards; Core iphonesimulator build green) |
| FND-0010 | medium | `FOUNDATIONMODELS_SWIFT_PATH` + monorepo tip ≠ mirror: CoreAI sources entram e quebram compile sem monorepo deps | open |

## Detalhe

### FND-0001
Swift em `packages/foundationmodels_apple/**` nunca passou por `xcodebuild`/`flutter build ios` documentado. Marcadores `// UPSTREAM(Un)` quebram contra bridge atual.

### FND-0002 / FND-0003
Bridge atual: health, availability, capabilities, createSession, disposeSession, respond (unary). Sem `respondStream` / cancel — ver `docs/specs/upstream-ios-bridge-extensions.md`.

### FND-0004
Arquivos em `docs/ci/`; CONTINUATION §5.

### FND-0005
`docs/parity.md` — evidence log vazio.

### FND-0009 — iOS Simulator consumer build blocked by upstream Core (2026-08-11)

**Reporter:** consumer sibling `../chat-on-device` (Flutter app, path deps to this monorepo).  
**Not fixed here** — intake only; no code patch in this repo for the unblock attempt after operator policy (consumer-only / no drive-by package edits).

**Reproduction (chat-on-device, iPhone 17 sim iOS 27.0, Xcode 27 beta):**

```bash
cd ../chat-on-device
flutter run -d FB43F1CD-0159-4C81-B842-4A38BCED5EE4 --dart-define=USE_MOCK_LLM=true
```

**Observed (mirror GitHub `from: "1.0.2"` / rev `9484ecc`):**

1. `Swift Compiler Error: Cannot find 'SecTaskCreateFromSelf' in scope`  
   - Source: `FoundationModelsCore.swift` (`processPCCEntitlementPresent`)  
   - Cause: `SecTask*` is under macOS-only Security module umbrella on iOS SDK (`SEC_OS_OSX` / no public `SecTask.h` for iPhoneSimulator). `import Security` is insufficient on iOS.
2. `Cannot find 'OCRTool' / 'BarcodeReaderTool' in scope`  
   - Source: `nativeVisionTool` in same file  
   - Cause: types live in macOS-only `_Vision_FoundationModels` overlay; not present on iPhoneSimulator SDK (Xcode 27 beta). Availability is `@available(macOS …)` which still compiles the body for iOS.
3. Secondary: Xcode 27 beta SPM registration crash  
   `NSMutableArray insertObjects:atIndexes: count of array (22) differs from count of index set (21)`  
   when package graph churns (duplicate/conflicting `Package.resolved` pins). Intermittent; first resolve sometimes succeeds.

**Impact:** Any Flutter iOS consumer that links `foundationmodels_apple` (even with Dart `--dart-define=USE_MOCK_LLM=true`) still compiles the native plugin + Core → **simulator smoke blocked**. Device tickets that assume sim CI remain untestable from consumer side.

**Suggested fix owners (upstream, not this consumer session):**

| Layer | Repo | Suggested work |
|-------|------|----------------|
| Core | `foundationmodels-swift` / monorepo Core | `#if os(macOS)` around SecTask PCC probe; fail-closed `false` on iOS |
| Core | same | `#if os(macOS)` around OCRTool/BarcodeReaderTool; typed unsupported on iOS |
| Mirror | `foundationmodels-swift` Package.swift | Keep CoreAI sources excluded (already) so path/local monorepo layout does not leak CoreAI into iOS plugin graph |
| Plugin | this repo `foundationmodels_apple` | Document that env `FOUNDATIONMODELS_SWIFT_PATH` must point at **mirror layout** or monorepo with CoreAI deps resolved; do not force absolute machine paths |
| CI | both | `flutter build ios --simulator` smoke in matrix |

**Related tickets:** TCK-0042 (this repo), upstream swift TCK once ops exists there, consumer chat-on-device paused-evidence device tickets.

### FND-0010 — Local monorepo path vs distribution mirror

When consumer pointed SPM at monorepo-style `FoundationModelsCore` package (includes `CoreAIInferenceBackend.swift`), build failed with `Unable to resolve module dependency: 'CoreAILanguageModels'`. Distribution mirror root `Package.swift` **excludes** CoreAI sources (by design, README). Plugin docs should state: local override path must match mirror product graph **or** full monorepo with CoreAI packages.



## Post-closeout / residual-optin findings

| ID | Severity | Status | Ticket |
|----|----------|--------|--------|
| FND-0009 | high | closed | TCK-0042 |
| FND-0010 | medium | open | TCK-0042 docs |
| FND-0007 | low | **closed** | TCK-0041 / ADR-0002 |
| FND-0008 | info | open | policy awareness (AGPL) |

**Programs:** POST-CLOSEOUT.md · RESIDUAL-OPTIN.md · epic TCK-0045 · RUN-20260811-residual-optin
