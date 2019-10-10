// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "rules_swift",
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/socketio/socket.io-client-swift", .upToNextMinor(from: "15.0.0")),
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git", from: "4.0.0")
    ]
)
