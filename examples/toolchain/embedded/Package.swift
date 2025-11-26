// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "rpi-4b-blink",
  dependencies: [
    .package(url: "https://github.com/apple/swift-mmio.git", branch: "0.1.1")
  ],
)
