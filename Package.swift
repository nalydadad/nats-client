// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ChatClient",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
    ],
    products: [
        .library(name: "ChatClient", targets: ["ChatClient"]),
    ],
    targets: [
        .target(name: "ChatClient"),
        .testTarget(name: "ChatClientTests", dependencies: ["ChatClient"]),
    ]
)
