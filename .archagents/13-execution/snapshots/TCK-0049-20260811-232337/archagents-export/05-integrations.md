# 05 — Integrations

| Integração | Tipo | Status |
|------------|------|--------|
| Apple Foundation Models | OS framework on-device | Via Swift core; **não medido** neste repo |
| foundationmodels-js (Swift core + ios-bridge) | Upstream monorepo | Source of truth; U1–U9 pendentes no bridge |
| foundationmodels-swift mirror | Distribuição | **Ainda não criado** (CONTINUATION §4) |
| chat-on-device | Consumidor git path | Sibling `../chat-on-device` pin SHA |
| pub.dev | Publicação | `publish_to: none` |

## Ausentes por design

- HTTP backend / cloud LLM no path happy
- Android/Windows/Linux nativo (mock only)
