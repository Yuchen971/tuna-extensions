// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "CardinalTuna",
  platforms: [.macOS(.v15)],
  products: [
    // Tuna loads the dynamic library from a framework bundle; see scripts/build.sh.
    .library(name: "CardinalTuna", type: .dynamic, targets: ["CardinalTuna"])
  ],
  dependencies: [
    .package(url: "https://github.com/tunaformac/TunaKit", exact: "1.22.0")
  ],
  targets: [
    .target(
      name: "CardinalTuna",
      dependencies: [.product(name: "TunaKit", package: "TunaKit")],
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .testTarget(
      name: "CardinalTunaTests",
      dependencies: ["CardinalTuna"],
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
  ]
)
