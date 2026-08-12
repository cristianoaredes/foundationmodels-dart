// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "FoundationModelsCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "FoundationModelsCore", targets: ["FoundationModelsCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMajor(from: "3.31.3")),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "FoundationModelsCore",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "Transformers", package: "swift-transformers"),
            ],
            linkerSettings: [
                // TCK-0150: allow test bundles to load when Xcode-beta SDK is newer than the
                // installed FoundationModels.framework (Attachment orientation symbols missing).
                .unsafeFlags(["-weak_framework", "FoundationModels"], .when(platforms: [.macOS])),
                // TCK-0227: Apple's model-callable vision tools (OCRTool /
                // BarcodeReaderTool) live in the `_Vision_FoundationModels`
                // cross-import overlay, which the compiler activates on its own
                // when Vision and FoundationModels are imported together — there
                // is no module to import by name. Both are weak-linked for the
                // same reason FoundationModels is: this binary must still load on
                // a system that lacks them, failing only if the path is actually
                // taken. Measured 2026-07-31: the overlay DOES resolve on this
                // machine (35 OCRTool symbols in the shared cache), unlike
                // Attachment itself (FND-0216).
                .unsafeFlags(["-weak_framework", "Vision"], .when(platforms: [.macOS])),
                .unsafeFlags(["-weak_framework", "_Vision_FoundationModels"], .when(platforms: [.macOS])),
                // TCK-0231 / FND-0171: CoreAI is pulled in via apple/coreai-models
                // (CoreAILM) and was strong-linked — SDK↔OS skew then aborted
                // dyld before main, blocking the daemon and every Swift test
                // bundle. Mirror the FoundationModels weak pattern; runtime
                // guards in CoreAIInferenceBackend fail closed with a typed
                // INFERENCE_BACKEND_UNAVAILABLE when symbols are missing.
                .unsafeFlags(["-weak_framework", "CoreAI"], .when(platforms: [.macOS])),
                // iOS: weak-link FoundationModels so the binary loads on iOS 17+
                // even though the framework only exists on iOS 26+.
                // CoreAI is NOT weak-linked on iOS — it does not exist in the
                // iPhoneSimulator SDK and the linker fails even with -weak_framework.
                .unsafeFlags(["-weak_framework", "FoundationModels"], .when(platforms: [.iOS]))
            ]
        ),
        .testTarget(
            name: "FoundationModelsCoreTests",
            dependencies: ["FoundationModelsCore"]
        )
    ]
)
