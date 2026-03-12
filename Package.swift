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
        .executable(name: "zion_svg2png", targets: ["ZionSVG2PNG"])
    ],
    dependencies: [
        .package(url: "https://github.com/nicolaregattieri/SwiftTerm.git", revision: "758b62157f629c8de618a50e8dbd6ba3f2a5db3b"),
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
            name: "ZionSVG2PNG",
            dependencies: []
        ),
        .testTarget(
            name: "ZionTests",
            dependencies: ["Zion"]
        )
    ]
)
