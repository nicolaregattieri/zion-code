// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Zion",
    defaultLocalization: "pt-BR",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Zion", targets: ["Zion"])
    ],
    dependencies: [
        .package(url: "https://github.com/nicolaregattieri/SwiftTerm.git", revision: "b13f85ac832dca4bbf3534a0c0d0a6d64fc49d1e"),
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
        .testTarget(
            name: "ZionTests",
            dependencies: ["Zion"]
        )
    ]
)
