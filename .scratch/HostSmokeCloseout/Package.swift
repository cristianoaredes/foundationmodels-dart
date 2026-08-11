// swift-tools-version: 6.4
import PackageDescription
let package = Package(
  name: "HostSmokeCloseout",
  platforms: [.macOS(.v27)],
  dependencies: [
    .package(name: "FoundationModelsIOSBridge", path: "/Users/cristiano/workspace/ai-workflow/foundationmodels-js/swift/ios-bridge"),
  ],
  targets: [
    .executableTarget(
      name: "HostSmokeCloseout",
      dependencies: [
        .product(name: "FoundationModelsIOSBridge", package: "FoundationModelsIOSBridge"),
      ]
    )
  ]
)
