# Specs — foundationmodels-dart

Design and planning documents for this repository. All specs assume the
upstream [`foundationmodels-js`](https://github.com/cristianoaredes/foundationmodels-js)
monorepo as the single source of truth for model behavior (upstream ADR-0002).

## Index

| Document | Description |
|---|---|
| [adr-0001-flutter-adapter.md](adr-0001-flutter-adapter.md) | **ADR-0001 (Accepted, 2026-08-09).** Foundational decision: a 3-package federated Flutter plugin whose transport is in-process JSON-RPC over platform channels, mirroring the daemon protocol v2. Defines the wire protocol, typed error mapping, tickets U1–U9, security invariants, the §17 coverage matrix, and the maximum-parity program (phases 0–8). **Read this first.** |
| [upstream-ios-bridge-extensions.md](upstream-ios-bridge-extensions.md) | Executable specification of upstream tickets U1–U9: the `FoundationModelsBridge` extensions (streaming, countTokens, vision, feedback, sessions, cancellation, duplex tools, MLX/CoreAI, PCC) that the adapter depends on. |
| [phase-2-streaming.md](phase-2-streaming.md) | Phase 2: multiplexed EventChannel streaming, `CancelToken` cooperative cancellation, typed `GENERATION_CANCELLED`. Depends on U1 + U6. |
| [phase-3-full-surface.md](phase-3-full-surface.md) | Phase 3: guided generation, multimodal, vision OCR/barcode, feedback attachment, `contextPolicy: guard`, policy/redaction. Depends on U2–U5. |
| [phase-4-tools.md](phase-4-tools.md) | Phase 4: duplex tool calling (stream-only callbacks), native tools (OCR/barcode), static tools, `SchemaMode.tool` sanitization. Depends on U7. |
| [phase-5-rag-and-desktop.md](phase-5-rag-and-desktop.md) | Phase 5: semantic index port (local RAG) and a pure-Dart daemon client over Unix socket for Flutter desktop macOS. |
| [phase-6-eval-traces.md](phase-6-eval-traces.md) | Phase 6: port of the eval harness (`@orqo/foundationmodels-eval`) and the end-to-end `traceId` traces contract. |
| [phase-7-agent-kit-mlx.md](phase-7-agent-kit-mlx.md) | Phase 7: agent kit port (tool loops, consume-once HITL, intent router, AG-UI events, optional MCP) plus MLX/CoreAI backend exposure via U8. |
| [phase-8-ecosystem.md](phase-8-ecosystem.md) | Phase 8: OpenAI-compatible server in Dart (`shelf`) and Dart ecosystem adapters (capability parity with the Vercel AI SDK adapter). |

## Reading order (for newcomers)

1. **[`CONTINUATION.md`](../../CONTINUATION.md)** at the repository root —
   current state of the work: what is done, what is in flight, and where to
   pick up.
2. **[adr-0001-flutter-adapter.md](adr-0001-flutter-adapter.md)** — the why
   and the whole map (wire protocol, phases 0–8, coverage matrix §17).
3. **[../protocol-mapping.md](../protocol-mapping.md)** and
   **[../parity.md](../parity.md)** — the method-by-method wire ↔ Dart ↔
   Swift table and the measured capability matrix.
4. The phase spec matching your current work (phases are sequential; phase N
   assumes the acceptance criteria of phases < N are met).
