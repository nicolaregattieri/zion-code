import XCTest
@testable import Zion

final class BridgeServiceTests: XCTestCase {
    private var tempDir: URL!
    private var cacheDir: URL!
    private var service: BridgeService!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BridgeServiceTests-\(UUID().uuidString)")
        cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BridgeServiceCache-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        service = BridgeService(
            fileManager: .default,
            cacheStore: BridgeCacheStore(fileManager: .default, baseDirectory: cacheDir)
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        try? FileManager.default.removeItem(at: cacheDir)
        super.tearDown()
    }

    func testAnalyzeCodexToClaudeUsesEmbeddedHomePath() throws {
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent(".agents/skills/oraculo"),
            withIntermediateDirectories: true
        )
        try """
        ---
        name: oraculo
        description: "Mirror and execute the Claude command."
        ---

        <!-- Zion Bridge: home=claude:.claude/commands/oraculo.md -->

        # oraculo

        ## Mirror Source
        Run the governance check and report only actionable drift.
        """.write(
            to: tempDir.appendingPathComponent(".agents/skills/oraculo/SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let analysis = try service.analyze(from: .codex, to: .claude, repositoryURL: tempDir)
        let row = try XCTUnwrap(analysis.rows.first)

        XCTAssertEqual(row.destinationRelativePath, ".claude/commands/oraculo.md")
        XCTAssertEqual(row.mappingKind, .knownMirror)
        XCTAssertEqual(row.action, .create)
        XCTAssertEqual(
            row.renderedContent?.trimmingCharacters(in: .whitespacesAndNewlines),
            "Run the governance check and report only actionable drift."
        )
    }

    func testApplyWritesOnlyDestinationFilesAndAvoidsBridgeFolder() throws {
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent(".agents/skills/oraculo"),
            withIntermediateDirectories: true
        )
        let sourceFile = tempDir.appendingPathComponent(".agents/skills/oraculo/SKILL.md")
        let sourceBody = """
        ---
        name: oraculo
        description: "Mirror and execute the Claude command."
        ---

        <!-- Zion Bridge: home=claude:.claude/commands/oraculo.md -->

        # oraculo

        ## Mirror Source
        Preserve the original command shape when syncing back.
        """
        try sourceBody.write(to: sourceFile, atomically: true, encoding: .utf8)

        let analysis = try service.analyze(from: .codex, to: .claude, repositoryURL: tempDir)
        _ = try service.apply(analysis, repositoryURL: tempDir)

        let destinationFile = tempDir.appendingPathComponent(".claude/commands/oraculo.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent(".bridge").path))
        XCTAssertEqual(try String(contentsOf: sourceFile, encoding: .utf8), sourceBody)

        let cacheFile = cacheDir.appendingPathComponent("\(RepoMemoryService.repoFingerprint(for: tempDir)).json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFile.path))
    }

    func testKnownMirrorCacheMakesSecondAnalysisDeterministic() throws {
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent(".agents/skills/ux-review"),
            withIntermediateDirectories: true
        )
        try """
        ---
        name: ux-review
        description: "Review Zion UX."
        ---

        # ux-review

        ## Mirror Source
        Audit the interface for friction.
        """.write(
            to: tempDir.appendingPathComponent(".agents/skills/ux-review/SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let first = try service.analyze(from: .codex, to: .claude, repositoryURL: tempDir)
        XCTAssertEqual(first.rows.first?.mappingKind, .newImport)

        _ = try service.apply(first, repositoryURL: tempDir)
        let second = try service.analyze(from: .codex, to: .claude, repositoryURL: tempDir)

        XCTAssertEqual(second.rows.first?.mappingKind, .knownMirror)
        XCTAssertEqual(second.rows.first?.destinationRelativePath, ".claude/commands/ux-review.md")
    }

    func testClaudeToCursorRendersNativeMdcShape() throws {
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent(".claude/commands"),
            withIntermediateDirectories: true
        )
        try """
        Review the changed workflow and keep the native command structure.
        """.write(
            to: tempDir.appendingPathComponent(".claude/commands/review-flow.md"),
            atomically: true,
            encoding: .utf8
        )

        let analysis = try service.analyze(from: .claude, to: .cursor, repositoryURL: tempDir)
        let row = try XCTUnwrap(analysis.rows.first)

        XCTAssertEqual(row.destinationRelativePath, ".cursor/rules/review-flow.mdc")
        XCTAssertEqual(row.action, .create)
        XCTAssertTrue(row.renderedContent?.contains("description:") == true)
        XCTAssertTrue(row.renderedContent?.contains("## Mirror Source") == true)
    }
}
