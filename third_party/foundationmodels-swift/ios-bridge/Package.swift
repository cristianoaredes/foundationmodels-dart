// swift-tools-version: 6.4

import PackageDescription

let package = Package(
  name: "FoundationModelsIOSBridge",
  platforms: [
    .macOS(.v14),
    .iOS(.v17)
  ],
  products: [
    .library(
      name: "FoundationModelsIOSBridge",
      type: .dynamic,
      targets: ["FoundationModelsIOSBridge"]
    )
  ],
  dependencies: [
    .package(path: "../FoundationModelsCore")
  ],
  targets: [
    .target(
      name: "FoundationModelsIOSBridge",
      dependencies: [
        .product(name: "FoundationModelsCore", package: "FoundationModelsCore")
      ]
    ),
    .testTarget(
      name: "FoundationModelsIOSBridgeTests",
      dependencies: ["FoundationModelsIOSBridge"]
    )
  ]
)
