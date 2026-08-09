# foundationmodels_platform_interface

Platform-interface contracts for the **FoundationModels Dart/Flutter adapter**
— the Dart port of [`foundationmodels-js`](https://github.com/cristianoaredes/foundationmodels-js)
(ADR-0001).

This package is **pure Dart** (no Flutter, no IO) and defines what every
provider/plugin must speak:

- **`FoundationModelsTransport`** — JSON-RPC-shaped envelope transport
  (`invoke` + multiplexed `streamEvents`), mirroring `docs/protocol.md` v2.
- **`FmMethods`** — stable method names (`foundationmodels.sessions.respond`,
  `foundationmodels.context.countTokens`, ...).
- **Typed stream events** — `RunStarted`, `TextDelta`, `StructuredDelta`,
  `ToolCallStart`, ..., `StreamDone`, `StreamError`, parsed via
  `FmStreamEvent.fromMap`. Every event carries `requestId`.
- **Typed errors** — sealed `FoundationModelsException` hierarchy with a 1:1
  mapping from the stable `error.data.code` string via
  `FoundationModelsException.fromError`.
- **Models** — `AvailabilityReport` (stable `reasonCode`s), `Usage`
  (`estimated` is `false` only when measured natively), `TokenCount`.

No implementations live here: the native plugin (`foundationmodels_apple`)
provides the platform-channel transport, and `package:foundationmodels`
provides the runtime and the deterministic offline mock provider.

## Invariants (inherited from upstream)

- The stable string `error.data.code` — not the numeric code — is the error
  contract.
- Errors never carry raw model content (`rawContent`).
- Guardrail violations and model refusals are never retryable; rate limits,
  timeouts, session-busy and transcript-mutation errors are.
