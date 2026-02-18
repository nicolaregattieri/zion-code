// swift-tools-version: 5.10

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
            ],
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=minimal"])
            ]
        ),
        .testTarget(
            name: "GraphForgeTests",
            dependencies: ["GraphForge"]
        )
    ]
)
