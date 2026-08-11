# Findings

| ID | Severity | Título | Status |
|----|----------|--------|--------|
| FND-0001 | high | `foundationmodels_apple` nunca compilado em Mac/device | open |
| FND-0002 | high | Streaming depende de U1 (ios-bridge) inexistente no bridge atual | open |
| FND-0003 | high | Cancel nativo depende de U6 | open |
| FND-0004 | medium | CI workflows não estão em `.github/workflows/` | open |
| FND-0005 | medium | Toda parity Flutter = `not measured` | open |
| FND-0006 | medium | Mirror `foundationmodels-swift` não existe | open |
| FND-0007 | low | `publish_to: none` — só consumo git | open |
| FND-0008 | info | AGPL-3.0-only no grafo de consumidores | open |

## Detalhe

### FND-0001
Swift em `packages/foundationmodels_apple/**` nunca passou por `xcodebuild`/`flutter build ios` documentado. Marcadores `// UPSTREAM(Un)` quebram contra bridge atual.

### FND-0002 / FND-0003
Bridge atual: health, availability, capabilities, createSession, disposeSession, respond (unary). Sem `respondStream` / cancel — ver `docs/specs/upstream-ios-bridge-extensions.md`.

### FND-0004
Arquivos em `docs/ci/`; CONTINUATION §5.

### FND-0005
`docs/parity.md` — evidence log vazio.
