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
# pubspec ref = este repo SHA
flutter pub get && flutter test
# device: ver TCK smoke no app + TCK-0003 neste repo
```
