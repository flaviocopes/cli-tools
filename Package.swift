// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "CliTools",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "CliToolsCore", targets: ["CliToolsCore"]),
    .executable(name: "clitools", targets: ["CliToolsCLI"]),
    .executable(name: "CliToolsApp", targets: ["CliToolsApp"])
  ],
  targets: [
    .target(name: "CliToolsCore"),
    .executableTarget(
      name: "CliToolsCLI",
      dependencies: ["CliToolsCore"]
    ),
    .executableTarget(
      name: "CliToolsApp",
      dependencies: ["CliToolsCore"]
    ),
    .testTarget(
      name: "CliToolsCoreTests",
      dependencies: ["CliToolsCore"]
    )
  ]
)
