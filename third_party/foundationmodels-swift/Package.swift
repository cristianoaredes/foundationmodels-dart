// swift-tools-version: 6.4
import PackageDescription

/// foundationmodels-swift — distribution mirror of FoundationModelsCore +
/// FoundationModelsIOSBridge for Flutter `foundationmodels_apple`.
///
/// All SPM dependencies are **versioned** so consumers can use:
///   .package(url: ".../foundationmodels-swift.git", from: "1.0.2")
///
/// CoreAI (`apple.coreai:*`) is fail-closed here: apple/coreai-models depends on
/// xgrammar@main (unstable), which SPM rejects under stable `from:` pins.
/// Full CoreAI: monorepo via FOUNDATIONMODELS_SWIFT_PATH.

let package = Package(
    name: "foundationmodels-swift",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "FoundationModelsCore", targets: ["FoundationModelsCore"]),
        .library(name: "FoundationModelsIOSBridge", targets: ["FoundationModelsIOSBridge"]),
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
            path: "FoundationModelsCore/Sources/FoundationModelsCore",
            exclude: [
                "CoreAIInferenceBackend.swift",
                "CoreAILanguageModel.swift",
            ],
            linkerSettings: [
                .unsafeFlags(["-weak_framework", "FoundationModels"], .when(platforms: [.macOS])),
                .unsafeFlags(["-weak_framework", "Vision"], .when(platforms: [.macOS])),
                .unsafeFlags(["-weak_framework", "_Vision_FoundationModels"], .when(platforms: [.macOS])),
                .unsafeFlags(["-weak_framework", "CoreAI"], .when(platforms: [.macOS])),
                // iOS: weak-link FoundationModels so the binary loads on iOS 17+
                // even though the framework only exists on iOS 26+.
                // CoreAI is NOT weak-linked on iOS — it does not exist in the
                // iPhoneSimulator SDK and the linker fails even with -weak_framework.
                .unsafeFlags(["-weak_framework", "FoundationModels"], .when(platforms: [.iOS])),
            ]
        ),
        .target(
            name: "FoundationModelsIOSBridge",
            dependencies: ["FoundationModelsCore"],
            path: "ios-bridge/Sources/FoundationModelsIOSBridge"
        ),
    ]
)
