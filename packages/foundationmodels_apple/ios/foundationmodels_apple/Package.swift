// swift-tools-version: 6.0
import PackageDescription
import Foundation

// The Swift core (FoundationModelsCore + FoundationModelsIOSBridge) is the
// single source of truth (ADR-0002 upstream).
//
// Path contract (TCK-0047 / FND-0010):
//   unset FOUNDATIONMODELS_SWIFT_PATH
//     → GitHub foundationmodels-swift from: "1.0.9" (CoreAI stub/excluded)
//   set = mirror-layout clone OR monorepo foundationmodels-js/swift
//     → path: $ROOT/FoundationModelsCore + $ROOT/ios-bridge
//   FORBIDDEN: monorepo Core alone / path without both packages
//     → SPM fails (e.g. CoreAILanguageModels missing)
// Recovery: unset env (mirror) or point at full monorepo swift/ with CoreAI deps.

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
                from: "1.0.9"
            )
        ]
    }

    static var targetDependencies: [Target.Dependency] {
        if useLocal {
            // Depend ONLY on the bridge product (avoids dual-class Core embedding).
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
        .iOS("17.0")
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
