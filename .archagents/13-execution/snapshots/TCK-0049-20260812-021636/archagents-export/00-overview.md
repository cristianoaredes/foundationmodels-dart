# 00 — Overview

> **Status:** v1 shippable (git-only) · 2026-08-11 · L3 open drain complete

## Elevator pitch

**foundationmodels-dart** é o adapter Dart/Flutter para o monorepo [FoundationModels JS](https://github.com/cristianoaredes/foundationmodels-js): expõe Apple Foundation Models (on-device) via canal JSON-RPC-shaped, com mock determinístico para CI. **Não** reimplementa lógica de modelo no Dart — o Swift core é a fonte da verdade.

## Estado do produto

| Camada | Estado |
|--------|--------|
| Core API + interface + apple plugin | Done · parity honest (tools duplex supported) |
| tools / agent | Done |
| MCP server + client + SSE | Done (`foundationmodels_mcp`) |
| daemon / policy / rag / eval / server / langchain | Present |
| Mirror SPM | `from: "1.0.4"` |
| pub.dev | Stay-private (ADR-0002) |
| Open tickets | TCK-0049 MLX blocked · TCK-0028 PCC blocked |

**Narrative status:** [`docs/PROJECT-STATUS.md`](../docs/PROJECT-STATUS.md)  
**Open backlog:** [`15-backlog/OPEN-BACKLOG.md`](15-backlog/OPEN-BACKLOG.md)

## Stack

- Dart **^3.12** · Flutter **≥ 3.27** (plugin Apple)
- Pub **workspace** (12 packages under `packages/`)
- Licença **AGPL-3.0-only**
- Platform: **iOS 27+ / macOS 27+**, Xcode 27

## Consumidores

- **chat-on-device** (sibling) — path/git consumer; package-side sim unblocked (TCK-0048)

## Fontes

- `README.md`, `CONTINUATION.md`, `docs/PROJECT-STATUS.md`, `docs/DELIVERY-LOG.md`
- `pubspec.yaml` (workspace)
- `packages/*`
