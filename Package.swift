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
        .package(url: "https://github.com/nicolaregattieri/SwiftTerm.git", revision: "f1afedc"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.8.1"),
        // Note: tree-sitter SPM grammars (alex-pinkus/tree-sitter-swift,
        // tree-sitter/tree-sitter-{typescript,rust,javascript,python,go}) all
        // ship Package.swift manifests that fail SPM 6.2 resolution (`path: "."`
        // bug produces `/Package.swift` lookup error). P12 ships a regex-based
        // Swift-only symbol extractor; tree-sitter integration deferred until
        // upstream grammars publish SPM 6.2-compatible manifests.
        // GRDB.swift — symbol DB store, T2+
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.7.1")
        // SQLiteVec — DEFERRED. jkrukowski/SQLiteVec vendored amalgamation
        // redefines `sqlite3_api_routines` and clashes with the macOS
        // system SQLite that ChatStorage already links. Phase 5 RAGStore
        // ships behind a `notImplemented` stub until we either (a) load
        // sqlite-vec as a runtime extension on the system sqlite3 via
        // `sqlite3_load_extension`, or (b) the bindings ship a flag to
        // skip the bundled amalgamation. Re-enable in Phase 5b.
    ],
    targets: [
        .executableTarget(
            name: "Zion",
            dependencies: [
                "SwiftTerm",
                "Sparkle",
                .product(name: "GRDB", package: "GRDB.swift")
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
