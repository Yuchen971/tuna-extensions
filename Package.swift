// swift-tools-version: 6.0
import PackageDescription

let tunaKit: Target.Dependency = .product(name: "TunaKit", package: "TunaKit")
let swiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
  name: "TunaExtensions",
  platforms: [.macOS(.v15)],
  products: [
    // Tuna loads each dynamic library from a framework bundle; see scripts/build.sh.
    .library(name: "CardinalTuna", type: .dynamic, targets: ["CardinalTuna"]),
    .library(name: "KeepAwakeTuna", type: .dynamic, targets: ["KeepAwakeTuna"]),
  ],
  dependencies: [
    .package(url: "https://github.com/tunaformac/TunaKit", exact: "1.22.0")
  ],
  targets: [
    .target(
      name: "CardinalTuna", dependencies: [tunaKit], path: "Cardinal/Sources",
      swiftSettings: swiftSettings),
    .testTarget(
      name: "CardinalTunaTests", dependencies: ["CardinalTuna"], path: "Cardinal/Tests",
      swiftSettings: swiftSettings),
    .target(
      name: "KeepAwakeTuna", dependencies: [tunaKit], path: "KeepAwake/Sources",
      swiftSettings: swiftSettings),
    .testTarget(
      name: "KeepAwakeTunaTests", dependencies: ["KeepAwakeTuna"], path: "KeepAwake/Tests",
      swiftSettings: swiftSettings),
  ]
)
