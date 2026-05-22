// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Zion",
    defaultLocalization: "pt-BR",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Zion", targets: ["Zion"]),
        .executable(name: "zion-mcp", targets: ["ZionMCP"])
    ],
    dependencies: [
        .package(url: "https://github.com/nicolaregattieri/SwiftTerm.git", revision: "c7d75a4"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.8.1")
    ],
    targets: [
        .executableTarget(
            name: "Zion",
            dependencies: [
                "SwiftTerm",
                "Sparkle"
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "ZionMCP",
            path: "Sources/ZionMCP"
        ),
        .testTarget(
            name: "ZionTests",
            dependencies: ["Zion"]
        ),
        .testTarget(
            name: "ZionMCPTests",
            dependencies: ["ZionMCP"],
            path: "Tests/ZionMCPTests"
        )
    ]
)
