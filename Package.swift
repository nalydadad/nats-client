// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NATSChatClient",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(name: "NATSChatClient", targets: ["NATSChatClient"]),
    ],
    targets: [
        .target(
            name: "NATSChatClient",
            path: "Sources/NATSChatClient"
        ),
        .testTarget(
            name: "NATSChatClientTests",
            dependencies: ["NATSChatClient"],
            path: "Tests/NATSChatClientTests"
        ),
    ]
)
