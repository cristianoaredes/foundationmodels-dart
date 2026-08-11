# SPC-0001 — Do phase 0 ao streaming on-device (MVP do package)

- **Status:** compiled → TCK-0001…0008 (+ epic)
- **DSC:** DSC-0001
- **Objetivo:** tornar `foundationmodels_apple` compilável e o streaming medido em device, com CI pure-Dart e parity honesty.

## Escopo in

1. Infra: CI dart.yml no `.github/` (quando token permitir)
2. Compile path Apple (Swift + FOUNDATIONMODELS_SWIFT_PATH)
3. Coordenação/tracking U1 + U6 (cross-repo)
4. Phase 2: smoke stream on-device + parity evidence
5. Documentar path unary enquanto stream não existe
6. Host/example mínimo opcional

## Escopo out

- Phases 3–8 completas (só tickets epic placeholders)
- Publicação pub.dev
- Mudanças no chat-on-device (repo sibling — tickets lá)

## Critérios machine-verifiable

| # | Check | Expect |
|---|-------|--------|
| 1 | `dart test` platform_interface + foundationmodels | all pass |
| 2 | `flutter analyze` foundationmodels_apple | clean |
| 3 | Evidence file em `14-verify/` com smoke device OU unary degrade documentado | exists + `aprovado` humano |
| 4 | `docs/parity.md` com ≥1 linha evidence | non-empty log |

## Dependências externas

- `foundationmodels-js` ios-bridge U1/U6
- Xcode 27 + device Apple Intelligence
