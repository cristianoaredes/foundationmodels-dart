# Protocolo de Atualização Incremental de `.archagents/`

> Este documento define como qualquer agente deve atualizar `.archagents/` após fazer uma mudança no código. É referenciado pelo `AGENTS.md` raiz e é de cumprimento obrigatório.

## Quando atualizar

Sempre que a mudança afetar qualquer uma destas dimensões:

- **Arquitetura** (camadas, padrões, boundaries) → `02-architecture.md`
- **Módulos** (novo módulo, reorganização, nova responsabilidade) → `03-modules.md`
- **Dados** (nova entidade, migration, schema) → `04-data-model.md`
- **Integrações** (nova API, mudança de contrato externo) → `05-integrations.md`
- **Infra/DevOps** (nova pipeline, ambiente, secret) → `06-infra-devops.md`
- **Segurança/Compliance** (authN/Z, crypto, PII, LGPD) → `07-security-compliance.md`
- **Convenções** (novo padrão adotado ou abandonado) → `08-conventions.md`
- **Domínio** (nova regra de negócio, novo termo no glossário) → `01-business-domain.md`
- **Decisão arquitetural** → criar novo ADR em `09-decisions/ADR-NNNN-*.md`

## Como atualizar

### Passo 1 — Identifique o delta

```bash
git diff --name-only HEAD~1 HEAD        # última mudança
# ou
git diff --name-only <base-ref>         # escopo explícito
```

### Passo 2 — Classifique o impacto

Para cada arquivo alterado, determine quais seções de `.archagents/` são afetadas consultando `.archagents/_meta.json` (que mapeia arquivos-fonte → seções Docs).

### Passo 3 — Atualize apenas as seções afetadas

**Regras duras:**

- Edite só as seções impactadas. **Não** "melhore" seções não afetadas.
- Atualize/adicione citações `path:Lstart-Lend` pra refletir o novo código.
- Se a mudança é arquiteturalmente significativa, crie um ADR em `09-decisions/`.
- Atualize `_meta.json` com os novos hashes SHA-1 dos arquivos-fonte tocados:

```bash
git hash-object <arquivo>
```

### Passo 4 — Verificação

Antes de considerar a atualização completa:

- [ ] Cada afirmação nova tem citação `path:Lstart-Lend`.
- [ ] As linhas citadas existem e correspondem ao que foi afirmado.
- [ ] `_meta.json` continua sendo JSON válido.
- [ ] Nenhuma seção não relacionada foi tocada.
- [ ] Se havia drift registrado nessa área, adicione entrada de reconciliação em `_drift-log.md`.

## O que **não** fazer

- **Não reescreva** arquivos `.archagents/*.md` inteiros. Use edições pontuais.
- **Não remova** citações antigas só porque você adicionou novas. Atualize-as.
- **Não duplique** informação entre seções. Cada fato vive em exatamente um lugar canônico, com referências cruzadas.
- **Não atualize** `.archagents/` para mudanças triviais (typo, rename local sem impacto público, refactor puramente interno sem mudança de comportamento).
- **Não apague** entradas antigas do `_drift-log.md`. Ele é append-only.

## Modo rápido (via skill)

Com o skill `codebase-ops` disponível, invoque `/ops-config docs` ou diga "atualiza a documentação após as últimas mudanças". O skill executa este protocolo automaticamente, com gate humano antes de aplicar edições.

## Casos especiais

### Código criado do zero (reconciliação greenfield)

Este projeto nasceu greenfield: as docs 00-10 descrevem a arquitetura **planejada** (ver DRIFT-20260808-01 em `_drift-log.md`). Ao criar código que concretiza uma seção, substitua os trechos `[PLANEJADO]` por descrição AS-IS com citações reais — isso é reconciliação de drift, não atualização comum.

### Grande refactor arquitetural

Se a mudança impacta 3+ seções de `.archagents/`, **pare e invoque o estágio Design** antes de implementar. Mudanças desse porte passam pelo ciclo completo Intake → Triage → Design → Execute → Verify.

### Mudança de dependência (bump de versão)

Bumps patch não exigem atualização. Bumps major/minor que mudam API pública SIM — atualize `05-integrations.md` ou `03-modules.md`. **Atenção especial:** `foundation_models_framework` é beta — qualquer bump exige smoke test em dispositivo físico (RSK-001) e atualização desta documentação.
