// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NATSChatClient",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),                                  // bumped to .v13 for nats.swift
    ],
    products: [
        .library(name: "NATSChatClient", targets: ["NATSChatClient"]),
        .executable(name: "ChatClientDemo", targets: ["ChatClientDemo"]),
    ],
    dependencies: [
        .package(url: "https://github.com/nats-io/nats.swift.git", from: "0.4.0"),
        // Pin swift-sodium to < 0.10.0: v0.10.0+ requires libsodium >= 1.0.19
        // (adds IpCrypt / AEGIS APIs) while Ubuntu 24.04 ships 1.0.18.
        .package(url: "https://github.com/jedisct1/swift-sodium.git", "0.9.0"..<"0.10.0"),
    ],
    targets: [
        .target(
            name: "NATSChatClient",
            path: "Sources/NATSChatClient"
        ),
        .executableTarget(
            name: "ChatClientDemo",
            dependencies: [
                "NATSChatClient",
                .product(name: "Nats", package: "nats.swift"),
            ],
            path: "Sources/ChatClientDemo"
        ),
        .testTarget(
            name: "NATSChatClientTests",
            dependencies: ["NATSChatClient"],
            path: "Tests/NATSChatClientTests"
        ),
    ]
)
