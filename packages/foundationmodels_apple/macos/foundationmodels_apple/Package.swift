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
        .macOS("27.0")
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
