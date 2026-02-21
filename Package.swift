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
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.0.7"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.8.0")
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
