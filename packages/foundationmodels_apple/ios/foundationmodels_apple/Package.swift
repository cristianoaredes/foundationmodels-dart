// swift-tools-version: 6.0
import PackageDescription
import Foundation

// The Swift core (FoundationModelsCore + FoundationModelsIOSBridge) is the
// single source of truth (ADR-0002 upstream). During development, point
// FOUNDATIONMODELS_SWIFT_PATH at a local checkout of the distribution mirror
// (or a subtree-split of the monorepo); otherwise consume the pinned mirror
// by URL, mirroring the daemon-darwin-arm64 distribution model (ADR-0001 §5).
let coreDep: Package.Dependency
let corePackageName: String
if let local = ProcessInfo.processInfo.environment["FOUNDATIONMODELS_SWIFT_PATH"] {
    coreDep = .package(path: local)
    corePackageName = URL(fileURLWithPath: local).lastPathComponent
} else {
    coreDep = .package(
        url: "https://github.com/cristianoaredes/foundationmodels-swift.git",
        from: "1.0.0"
    )
    corePackageName = "foundationmodels-swift"
}

let package = Package(
    name: "foundationmodels_apple",
    platforms: [
        .iOS("27.0")
    ],
    products: [
        .library(name: "foundationmodels-apple", targets: ["foundationmodels_apple"])
    ],
    dependencies: [coreDep],
    targets: [
        .target(
            name: "foundationmodels_apple",
            dependencies: [
                .product(name: "FoundationModelsCore", package: corePackageName),
                .product(name: "FoundationModelsIOSBridge", package: corePackageName)
            ],
            path: "Sources/foundationmodels_apple"
        )
    ]
)
