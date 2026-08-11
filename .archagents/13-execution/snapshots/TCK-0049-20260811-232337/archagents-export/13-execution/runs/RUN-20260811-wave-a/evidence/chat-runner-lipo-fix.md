# TCK-0048 class A fix (chat-on-device)

**Root cause:** Xcode 27 `lipo -verify_arch arm64 x86_64` fails (`-verify_arch requires exactly one input file` when multi-arch) even though the fat Flutter.framework contains both arches. Flutter 3.44 `thinFramework` then aborts.

**Fix (consumer):** force `ARCHS=arm64` in `ios/Flutter/{Debug,Release}.xcconfig`, project.pbxproj, Podfile post_install; exclude x86_64 for simulator.

**Result:** `flutter build ios --simulator --no-codesign` → `✓ Built build/ios/iphonesimulator/Runner.app`
