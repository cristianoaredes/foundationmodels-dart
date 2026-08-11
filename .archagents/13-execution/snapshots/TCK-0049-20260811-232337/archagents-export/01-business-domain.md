# 01 — Business domain

## Domínio

Primitivas de IA **on-device** para apps Dart/Flutter: classify, extract, rank, summarize, respond, stream, sessões, guided generation (schema), com degradê explícito para mock quando Apple indisponível.

## Regras de negócio / invariantes (upstream, não negociáveis)

1. **Sem cloud silenciosa** — sem provider → mock; nunca inventar backend de rede.
2. **Erros tipados** — `error.data.code` é o contrato; nunca fake success.
3. **`instructions` é canal trusted** — nunca concatenar user input/tool/web em instructions.
4. **Fail-closed security** — imagens só com allowlist; erros sem `rawContent` do modelo.
5. **Parity honest** — `supported` só com evidence on-device (data + device + smoke).
6. **Só streaming é verdadeiramente interruptível** — cancel de unary para a espera, não a geração.

## Stakeholders

| Quem | Interesse |
|------|-----------|
| Apps Orqo / chat-on-device | Consumir API estável on-device |
| Manutenção Swift core | Paridade daemon ↔ bridge ↔ Flutter |
| CI/Linux | Mock + testes pure-Dart sem Mac |

## Fontes

- `CONTINUATION.md` §6
- `docs/parity.md`
