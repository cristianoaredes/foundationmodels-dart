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
| FND-0010 | medium | `FOUNDATIONMODELS_SWIFT_PATH` + monorepo tip ≠ mirror: CoreAI sources entram e quebram compile sem monorepo deps | **closed** (TCK-0047 path contract docs) |
| FND-0011 | medium | SPM platform floor (`iOS 27`/`macOS 27`) é app-wide, não por code-path — bloqueia fallback Gemma em OS mais antigo mesmo quando AFM não seria usado | open — TCK-0060 |

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

**Closed 2026-08-11 (TCK-0047):** decision table + recovery in `packages/foundationmodels_apple/README.md`, `Package.swift` comments (ios/macos), CONTINUATION §3/§6.

### FND-0011 — SPM platform floor is app-wide, defeats OS-version fallback (2026-08-12)

**Reporter:** consumer sibling `../chat-on-device`, durante triagem de residual do backend
Gemma (TCK-0059/TCK-0060 nesse consumer).

**Observação:** `chat-on-device` implementa uma cascata AFM → Gemma → GGUF (ADR-0009
naquele repo) para que dispositivos sem Apple Intelligence caiam num backend local
alternativo. Isso já funciona corretamente na dimensão de **hardware** (chip sem NPU
elegível → AFM reporta indisponível, cascata segue). **Não funciona** na dimensão de
**versão de OS**, porque o piso de plataforma é declarado no nível do pacote SPM, não
por code-path:

```swift
// packages/foundationmodels_apple/ios/foundationmodels_apple/Package.swift:51-53
platforms: [.iOS("27.0")]

// third_party/foundationmodels-swift/Package.swift:16-18
platforms: [.iOS(.v27), .macOS(.v27)]

// third_party/foundationmodels-swift/ios-bridge/Package.swift:7-10
platforms: [.macOS(.v27), .iOS(.v27)]
```

Qualquer app que linke `foundationmodels_apple` via SPM **precisa** ter
`IPHONEOS_DEPLOYMENT_TARGET >= 27.0` — o Xcode recusa resolver o grafo de pacotes
caso contrário. Isso vale pro binário **inteiro**, incluindo code paths (como o
adapter Gemma) que nunca tocam a API da Apple.

**Comparação concreta (evidência, 2026-08-12):**

| Pacote | Piso declarado |
|---|---|
| `foundationmodels_apple` / `foundationmodels-swift` (este repo) | iOS 27.0 / macOS 27.0 |
| `flutter_gemma` 1.5.2 (`ios/flutter_gemma.podspec`) — o fallback real do consumidor | iOS 16.0 |

**Por que não é resolvido por `@available` já:** procurei por guardas
`@available(iOS 27, *)` + weak-link do framework `FoundationModels` no lado iOS —
não existem. O único weak-link presente é `-weak_framework FoundationModels` em
`FoundationModelsCore/Package.swift`, mas **só para macOS** (`.when(platforms:
[.macOS])`) e por outro motivo (TCK-0150: mismatch Xcode-beta SDK vs framework
instalado, não "suportar OS mais antigo em runtime").

**Reprodução (chat-on-device, 2026-08-12):**

```bash
# iPhone 14 físico (iPhone14,7 — nunca terá AFM, chip < A17 Pro) em iOS 26.5.2:
$ flutter run -d 00008110-0002303E3E01401E --debug
Error launching application on iPhone's Husé.
…iPhone's Husé's iOS 26.5.2 doesn't match Runner.app's iOS 27.0 deployment target.
```

O device é exatamente o cenário ideal pra validar o fallback (hardware permanentemente
inelegível pra AFM) mas nem chega a instalar o app, por um motivo não relacionado ao
chip.

**Impacto:** qualquer consumidor que queira "AFM quando disponível, Gemma/GGUF como
fallback universal" fica limitado ao piso de OS do AFM (27.0) pra rodar em QUALQUER
device — inclusive os que só usariam o fallback. Isso reduz o alcance real do produto
pra exatamente os devices que já teriam AFM, na prática anulando parte do valor do
fallback.

**Sugestão de fix (não trivial — mudança de arquitetura, não código deste finding):**

| Camada | Sugestão |
|---|---|
| `FoundationModelsCore` / `ios-bridge` / `foundationmodels-swift` | Baixar `platforms:` pro mínimo real necessário pelos code-paths não-AFM (alinhar ao piso do maior consumidor de fallback, ex. iOS 16/macOS 13) |
| Chamadas diretas à API `FoundationModels` da Apple | Envolver em `@available(iOS 27, *)` / `@available(macOS 27, *)` + weak-link `FoundationModels.framework` também no **iOS** (hoje só macOS, e por outro motivo) |
| `foundationmodels_apple` (plugin) | Mesma redução de piso nos dois `Package.swift` (ios/macos); `checkAvailability()` já retorna `available:false` com reasonCode — só precisa deixar de exigir OS novo pra sequer compilar/instalar |

**Related:** TCK-0042/FND-0009 (gate de build anterior, já fechado — erro de compilação,
não de deployment target); `chat-on-device` ADR-0009 (cascata multi-backend) e
TCK-0059/TCK-0060 (residual Gemma real, onde este finding foi descoberto).

**Ticket:** TCK-0060 (intake — avaliação de arquitetura, não iniciado).

## Post-closeout / residual-optin findings

| ID | Severity | Status | Ticket |
|----|----------|--------|--------|
| FND-0009 | high | closed | TCK-0042 |
| FND-0010 | medium | **closed** | TCK-0047 |
| FND-0007 | low | **closed** | TCK-0041 / ADR-0002 |
| FND-0008 | info | open | policy awareness (AGPL) · TCK-0052 |

**Programs:** POST-CLOSEOUT · RESIDUAL-OPTIN · **NEXT-WAVE** (TCK-0046) · RUN residual-optin
