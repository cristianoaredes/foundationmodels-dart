# Playbook — TCK-0042 iOS Simulator Core guards

**Ticket:** TCK-0042  
**Effort:** M  
**Risk:** medium (Swift Core shared surface; must not break macOS host smokes)

## Preconditions

- Xcode 27 / iOS 27 SDK  
- Monorepo: `FOUNDATIONMODELS_SWIFT_PATH` or edit both monorepo + `third_party/foundationmodels-swift`  
- Do **not** mark iOS FM generation supported from this playbook  

## Steps

1. **Locate** `processPCCEntitlementPresent` and `nativeVisionTool` in Core.  
2. **Wrap** SecTask path in `#if os(macOS)` / `#else return false`.  
3. **Wrap** OCRTool/BarcodeReaderTool in `#if os(macOS)` / `#else` typed unsupported.  
4. **Sync** monorepo Core ↔ `third_party/foundationmodels-swift` sources.  
5. **Docs:** plugin README + Package.swift comments for path layout (FND-0010).  
6. **Build evidence:**  
   ```bash
   # example or consumer with path deps
   flutter build ios --simulator
   ```  
7. **Regression:** re-run macOS HostSmoke duplex **or** pure-Dart tests + note.  
8. **Close** FND-0009 when sim build green; leave device FM tickets as-is.  

## Rollback

- Revert Core guards if macOS vision/PCC probe regressions.  
- Do not publish mirror until macOS smoke still green.  

## Next

- TCK-0044 publish mirror tag including these sources.
