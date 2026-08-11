# 04 — Data model / contratos

## Wire protocol

- Envelopes `{id, method, params}` → result map
- Stream events: `run_started`, `message_start`, `text_delta`, `structured_delta`, tool_call_*, `message_end`, `done`, `error`
- Erros: `NSError` / `FmTransportError` com `data.code` estável

## Tipos Dart principais

| Tipo | Onde |
|------|------|
| `FmStreamEvent` (sealed) | `platform_interface/.../events.dart` |
| `AvailabilityReport` + reasonCodes | `platform_interface/.../models.dart` |
| `FmSession` (lazy mint `ses_*`) | `foundationmodels/.../session.dart` |
| `FmSchema` | `foundationmodels/.../schema.dart` |
| `CancelToken` | `foundationmodels/.../cancel.dart` |
| `FoundationModelsException` | platform_interface errors |

## Fontes

- `docs/protocol-mapping.md` (se existir) · interface package
- Upstream `docs/protocol.md` (foundationmodels-js)
