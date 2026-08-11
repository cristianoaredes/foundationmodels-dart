# 10 — Runbooks

## Validar pure-Dart (qualquer máquina)

```bash
flutter pub get
(cd packages/foundationmodels_platform_interface && dart test && dart analyze)
(cd packages/foundationmodels && dart test && dart analyze)
(cd packages/foundationmodels_apple && flutter analyze)
```

Esperado: **145 tests green**, analyze limpo.

## Compilar Apple (Mac + Xcode 27)

1. Checkout `foundationmodels-js` com Swift core  
2. `export FOUNDATIONMODELS_SWIFT_PATH=...`  
3. Resolver U1+U6 **ou** comentar paths UPSTREAM que não compilam  
4. `flutter build ios` / host app de exemplo  
5. Registrar evidence em `docs/parity.md` + VER no `.archagents/14-verify/`

## Publicar CI

Copiar `docs/ci/*.yml` → `.github/workflows/` com token que tenha scope `workflow`.

## Consumidor chat-on-device

```bash
# no app sibling
# pubspec ref = este repo SHA  (ou mirror ≥1.0.3 após TCK-0044)
flutter pub get && flutter test
# iOS sim: bloqueado até TCK-0042 (SecTask/OCR guards) — ver POST-CLOSEOUT.md
# device FM: só com hardware Apple Intelligence (não A14 iPad)
```

## Post-closeout — ordem de execução

Ver [15-backlog/POST-CLOSEOUT.md](15-backlog/POST-CLOSEOUT.md).

1. `/ops-work TCK-0043` — VER + ship hygiene  
2. `/ops-work TCK-0042` — iOS sim Core guards (playbook PB-POST-CLOSEOUT-0042)  
3. `/ops-work TCK-0044` — mirror ≥1.0.3 (gate humano no push de tag)  
4. `/ops-work TCK-0040` — chat-on-device integration  

