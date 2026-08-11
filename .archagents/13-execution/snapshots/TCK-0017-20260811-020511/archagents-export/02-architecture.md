# 02 — Architecture (AS-IS)

## Padrão

**Federated plugin** (platform_interface + app-facing package + apple implementation) sobre **transport JSON-RPC v2** (envelopes daemon-shaped), com **mock provider** no pure-Dart.

```
package:foundationmodels
        │ implements FmProvider / TransportProvider
        ▼
foundationmodels_platform_interface
        │ MethodChannel foundationmodels/rpc
        │ EventChannel  foundationmodels/streams
        ▼
foundationmodels_apple (iOS + macOS, SPM)
        │ FoundationModelsBridge.shared
        ▼
FoundationModelsCore + IOSBridge (upstream monorepo)
        ▼
Apple Foundation Models (device)
```

## Limites

- **Dart não contém lógica de modelo.**
- Plugin Apple compila contra API **alvo** do bridge (U1–U7); bridge **atual** só tem health/availability/capabilities/createSession/disposeSession/respond (unary).

## Fontes

- `README.md` architecture diagram
- `packages/foundationmodels/lib/src/runtime.dart`
- `packages/foundationmodels_apple/lib/src/foundationmodels_apple.dart`
- `docs/specs/upstream-ios-bridge-extensions.md` §0.1
