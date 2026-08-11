# Playbook — TCK-0048 chat-on-device Runner lipo

## Steps

1. `cd ../chat-on-device && flutter clean && flutter pub get`  
2. `flutter build ios --simulator` → capture log  
3. Classify A (Flutter lipo) / B (package Core) / C (pin)  
4. Fix owner repo only  
5. Re-run build; smoke mock if green  
6. Evidence under RUN; update ticket  

## Rollback

Revert consumer ios/Flutter config; package untouched if class A.
