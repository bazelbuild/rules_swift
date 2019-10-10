// swift-tools-version:4.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "rules_swift",
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/socketio/socket.io-client-swift", .branch("master")),
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git", .branch("master"))
    ]
)
