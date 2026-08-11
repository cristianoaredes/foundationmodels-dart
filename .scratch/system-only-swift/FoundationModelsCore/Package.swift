// swift-tools-version: 6.4
import PackageDescription
let package = Package(
  name: "FoundationModelsCore",
  platforms: [.macOS(.v27), .iOS(.v27)],
  products: [.library(name: "FoundationModelsCore", targets: ["FoundationModelsCore"])],
  targets: [
    .target(
      name: "FoundationModelsCore",
      dependencies: [],
      linkerSettings: [
        .unsafeFlags(["-weak_framework", "FoundationModels"], .when(platforms: [.macOS])),
        .unsafeFlags(["-weak_framework", "Vision"], .when(platforms: [.macOS])),
        .unsafeFlags(["-weak_framework", "_Vision_FoundationModels"], .when(platforms: [.macOS])),
        .unsafeFlags(["-weak_framework", "CoreAI"], .when(platforms: [.macOS])),
      ]
    )
  ]
)
