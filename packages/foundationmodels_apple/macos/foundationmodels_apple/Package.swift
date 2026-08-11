// swift-tools-version: 6.0
import PackageDescription
import Foundation

// macOS mirror of ios/foundationmodels_apple/Package.swift.
//
// SwiftPM requires a target's sources to live inside the package directory,
// so this package cannot point `path:` at ../../ios/... — the thin plugin
// source file is duplicated under macos/.../Sources instead. Keep both copies
// byte-identical (the file is a pure channel<->bridge translator; all logic
// lives upstream in FoundationModelsCore). See the package README.
//
// Local development:
//   export FOUNDATIONMODELS_SWIFT_PATH=/path/to/foundationmodels-js/swift
// Distribution: foundationmodels-swift mirror (TCK-0015).

enum SwiftCoreDeps {
    static let useLocal = ProcessInfo.processInfo.environment["FOUNDATIONMODELS_SWIFT_PATH"] != nil
    static let root = ProcessInfo.processInfo.environment["FOUNDATIONMODELS_SWIFT_PATH"] ?? ""

    static var dependencies: [Package.Dependency] {
        if useLocal {
            return [
                .package(path: root + "/FoundationModelsCore"),
                .package(path: root + "/ios-bridge"),
            ]
        }
        return [
            .package(
                url: "https://github.com/cristianoaredes/foundationmodels-swift.git",
                from: "1.0.3"
            )
        ]
    }

    static var targetDependencies: [Target.Dependency] {
        if useLocal {
            // Depend ONLY on the bridge product. Linking Core again embeds a
            // second copy of FoundationModelsCore (dual-class crashes / cast
            // failures). The bridge already re-exports Core transitively.
            return [
                .product(name: "FoundationModelsIOSBridge", package: "ios-bridge"),
            ]
        }
        return [
            .product(name: "FoundationModelsIOSBridge", package: "foundationmodels-swift"),
        ]
    }
}

let package = Package(
    name: "foundationmodels_apple",
    platforms: [
        .macOS("27.0")
    ],
    products: [
        .library(name: "foundationmodels-apple", targets: ["foundationmodels_apple"])
    ],
    dependencies: SwiftCoreDeps.dependencies,
    targets: [
        .target(
            name: "foundationmodels_apple",
            dependencies: SwiftCoreDeps.targetDependencies,
            path: "Sources/foundationmodels_apple",
            // Plugin is a thin channel↔bridge translator; FlutterResult / dict
            // callbacks are not Sendable. Use Swift 5 language mode so Task
            // hops to Core stay buildable under Xcode 27 + monorepo Swift 6.4.
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        )
    ]
)
