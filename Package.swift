// swift-tools-version:4.0

import PackageDescription

let package = Package(
  name: "Concurrent",
  products: [
    .library(
      name: "Concurrent",
      targets: ["Concurrent"]),
    ],
  dependencies: [
    .package(url: "https://github.com/typelift/SwiftCheck.git", .branch("master"))
  ],
  targets: [
    .target(
      name: "Concurrent"),
    .testTarget(
      name: "ConcurrentTests",
      dependencies: ["Concurrent", "SwiftCheck"]),
    ]
)

