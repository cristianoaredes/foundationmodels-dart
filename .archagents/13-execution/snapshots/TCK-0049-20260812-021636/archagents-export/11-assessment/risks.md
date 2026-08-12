# Risks

| ID | Risco | Mitigação |
|----|-------|-----------|
| RSK-0001 | Consumidores (chat-on-device) assumem stream real e falham em device | Smoke TCK + degrade mock/unary documentado |
| RSK-0002 | U1/U6 só em monorepo JS — descompasso de release | Tickets cross-repo; pin SHAs; parity honesty |
| RSK-0003 | Xcode 27 / iOS 27 excluem devices atuais do time | Documentar toolchain; path unary + mock |
| RSK-0004 | AGPL em app fechado | Reavaliação de licença antes de produto |
| RSK-0005 | CI ausente → regressão silent no pure-Dart | Instalar `docs/ci/dart.yml` (TCK-0008) |
