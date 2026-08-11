# foundationmodels-swift

Distribution mirror of **FoundationModelsCore** + **FoundationModelsIOSBridge**
for [`foundationmodels-dart`](https://github.com/cristianoaredes/foundationmodels-dart).

## Install (SPM — versioned)

```swift
dependencies: [
  .package(
    url: "https://github.com/cristianoaredes/foundationmodels-swift.git",
    from: "1.0.2"
  )
],
// target deps:
.product(name: "FoundationModelsCore", package: "foundationmodels-swift"),
.product(name: "FoundationModelsIOSBridge", package: "foundationmodels-swift"),
```

```swift
import FoundationModelsCore
import FoundationModelsIOSBridge
```

## Flutter plugin

```bash
# Preferred for full CoreAI + monorepo tip:
export FOUNDATIONMODELS_SWIFT_PATH=/path/to/foundationmodels-js/swift

# Or leave unset → plugin Package.swift uses this GitHub package from: "1.0.2"
```

## Scope notes

| Backend | In this package |
|---------|-----------------|
| `apple.system` (Foundation Models) | ✅ |
| MLX (`apple.mlx:*`) | ✅ (via mlx-swift-lm) |
| CoreAI (`apple.coreai:*`) | ❌ fail-closed stub — monorepo only |

Reason: `apple/coreai-models` depends on `xgrammar` via `branch: "main"`, which
SPM forbids under stable `from:` version roots.

## Source of truth

[foundationmodels-js](https://github.com/cristianoaredes/foundationmodels-js) `swift/`.

## Platforms

iOS 27+ / macOS 27+.
