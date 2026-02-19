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
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.0.7")
    ],
    targets: [
        .executableTarget(
            name: "GraphForge",
            dependencies: [
                "SwiftTerm"
            ],
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
