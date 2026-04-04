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
        .package(url: "https://github.com/nicolaregattieri/SwiftTerm.git", revision: "33a6505953cc6dd0e49589d28ce9dc85bfe640ca"),
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
