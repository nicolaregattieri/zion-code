// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GraphForge",
    defaultLocalization: "pt-BR",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "GraphForge", targets: ["GraphForge"])
    ],
    targets: [
        .executableTarget(
            name: "GraphForge",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "GraphForgeTests",
            dependencies: ["GraphForge"]
        )
    ]
)
