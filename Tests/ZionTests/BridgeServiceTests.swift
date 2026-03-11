import XCTest
@testable import Zion

final class BridgeServiceTests: XCTestCase {
    private var tempDir: URL!
    private let service = BridgeService()

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BridgeServiceTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testInitializePackageCreatesCanonicalStructure() throws {
        let state = try service.initializePackage(repositoryURL: tempDir)

        XCTAssertTrue(state.exists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent(".bridge/manifest.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent(".bridge/skills").path))
    }

    func testImportCodexLoadsGuidanceRulesAndSkills() throws {
        try "Root context".write(to: tempDir.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent(".agents/rules"), withIntermediateDirectories: true)
        try "Rule body".write(to: tempDir.appendingPathComponent(".agents/rules/safety.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent(".agents/skills/documenter"), withIntermediateDirectories: true)
        try """
        ---
        name: documenter
        description: Keep docs in sync.
        ---

        # Documenter
        """.write(
            to: tempDir.appendingPathComponent(".agents/skills/documenter/SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let state = try service.importConfiguration(from: .codex, repositoryURL: tempDir)

        XCTAssertEqual(state.items.count, 3)
        XCTAssertEqual(state.manifest.lastImportedTarget, .codex)
        XCTAssertTrue(state.items.contains { $0.kind == .guidance })
        XCTAssertTrue(state.items.contains { $0.kind == .rule })
        XCTAssertTrue(state.items.contains { $0.kind == .skill })
    }

    func testPreviewSyncCreatesUpdateAndRemoveOperations() throws {
        let initialState = BridgeProjectState(
            exists: true,
            manifest: BridgeManifest(),
            items: [
                BridgeItem(kind: .guidance, slug: "main", title: "Main", summary: "Guide", content: "Use Zion\n"),
                BridgeItem(kind: .rule, slug: "safety", title: "Safety", summary: "Rule", content: "Never edit blindly\n")
            ],
            warnings: []
        )
        _ = try service.initializePackage(repositoryURL: tempDir)
        try "old".write(to: tempDir.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent(".agents/rules"), withIntermediateDirectories: true)
        try "stale".write(to: tempDir.appendingPathComponent(".agents/rules/legacy.md"), atomically: true, encoding: .utf8)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(initialState.manifest)
        try data.write(to: tempDir.appendingPathComponent(".bridge/manifest.json"))
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent(".bridge/guidance"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent(".bridge/rules"), withIntermediateDirectories: true)
        try "Use Zion\n".write(to: tempDir.appendingPathComponent(".bridge/guidance/main.md"), atomically: true, encoding: .utf8)
        try "Never edit blindly\n".write(to: tempDir.appendingPathComponent(".bridge/rules/safety.md"), atomically: true, encoding: .utf8)

        let preview = try service.previewSync(to: .codex, repositoryURL: tempDir)

        XCTAssertTrue(
            preview.operations.contains { $0.relativePath == "AGENTS.md" && $0.kind == .update },
            "\(preview.operations)"
        )
        XCTAssertTrue(
            preview.operations.contains { $0.relativePath == ".agents/rules/safety.md" && $0.kind == .create },
            "\(preview.operations)"
        )
        XCTAssertTrue(
            preview.operations.contains { $0.relativePath == ".agents/rules/legacy.md" && $0.kind == .remove },
            "\(preview.operations)"
        )
    }

    func testApplySyncWritesRenderedFiles() throws {
        _ = try service.initializePackage(repositoryURL: tempDir)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent(".bridge/guidance"), withIntermediateDirectories: true)
        try "Shared context\n".write(to: tempDir.appendingPathComponent(".bridge/guidance/main.md"), atomically: true, encoding: .utf8)

        let preview = try service.previewSync(to: .claude, repositoryURL: tempDir)
        let state = try service.applySync(preview, repositoryURL: tempDir)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("CLAUDE.md").path))
        XCTAssertTrue(state.manifest.enabledTargets.contains(.claude))
    }
}
