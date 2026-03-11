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

    func testImportCodexMirroredSkillBecomesClaudeCommandMirror() throws {
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent(".claude/commands"), withIntermediateDirectories: true)
        try "Use the original Claude workflow.\n".write(
            to: tempDir.appendingPathComponent(".claude/commands/oraculo.md"),
            atomically: true,
            encoding: .utf8
        )

        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent(".agents/skills/oraculo"), withIntermediateDirectories: true)
        try """
        ---
        name: oraculo
        description: Use when the user wants tool-level diagnosis, friction analysis, or governance changes rather than section work.
        ---

        Repo-local Codex skill generated from `.claude/commands/oraculo.md`.

        Workflow:
        1. Read `.claude/commands/oraculo.md` and follow it as the reference procedure.
        2. Treat `.claude/*` as immutable governance input unless the user explicitly asks to edit it.
        3. Prefer mirrored project rules in `.agents/rules/*.md` when the same rule exists there.
        4. Create or edit project files outside `.claude/`.
        """.write(
            to: tempDir.appendingPathComponent(".agents/skills/oraculo/SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let state = try service.importConfiguration(from: .codex, repositoryURL: tempDir)
        let item = try XCTUnwrap(state.items.first(where: { $0.slug == "oraculo" }))

        XCTAssertEqual(item.kind, .command)
        XCTAssertEqual(item.strategy, .claudeCommandMirror)
        XCTAssertEqual(item.mirrorReferencePath, ".claude/commands/oraculo.md")
        XCTAssertEqual(item.sourceHint, ".agents/skills/oraculo/SKILL.md")
        XCTAssertEqual(item.content, "Use the original Claude workflow.\n")
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

    func testPreviewSyncToCodexUsesMirroredWrapperForClaudeCommands() throws {
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent(".claude/commands"), withIntermediateDirectories: true)
        try "Use the original Claude workflow.\n".write(
            to: tempDir.appendingPathComponent(".claude/commands/oraculo.md"),
            atomically: true,
            encoding: .utf8
        )
        _ = try service.importConfiguration(from: .claude, repositoryURL: tempDir)

        let preview = try service.previewSync(to: .codex, repositoryURL: tempDir)
        let operation = try XCTUnwrap(preview.operations.first { $0.relativePath == ".agents/skills/oraculo/SKILL.md" })

        XCTAssertEqual(operation.compatibility, .native)
        XCTAssertEqual(operation.kind, .create)
        XCTAssertTrue(operation.renderedContent?.contains("Repo-local Codex skill generated from `.claude/commands/oraculo.md`.") == true)
        XCTAssertTrue(operation.renderedContent?.contains("Read `.claude/commands/oraculo.md` and follow it as the reference procedure.") == true)
    }

    func testImportCodexSkillMatchingClaudeCommandBecomesNormalizedClaudeCommand() throws {
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent(".claude/commands"), withIntermediateDirectories: true)
        try "You are a senior UX/UI designer reviewing the Zion macOS Git client.\n".write(
            to: tempDir.appendingPathComponent(".claude/commands/ux-review.md"),
            atomically: true,
            encoding: .utf8
        )

        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent(".agents/skills/ux-review"), withIntermediateDirectories: true)
        try """
        ---
        name: ux-review
        description: Review Zion UX/UI and propose concrete SwiftUI improvements with code-level guidance.
        ---

        # UX Review

        Mirror and execute the workflow defined for Claude command parity using Codex skills.

        ## Workflow
        You are a senior UX/UI designer reviewing the Zion macOS Git client.

        Read `.agents/skills/documenter/SKILL.md` when the review also affects docs.
        """.write(
            to: tempDir.appendingPathComponent(".agents/skills/ux-review/SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let state = try service.importConfiguration(from: .codex, repositoryURL: tempDir)
        let item = try XCTUnwrap(state.items.first(where: { $0.slug == "ux-review" }))

        XCTAssertEqual(item.kind, .command)
        XCTAssertEqual(item.strategy, .codexSkillMirror)
        XCTAssertEqual(item.mirrorReferencePath, ".claude/commands/ux-review.md")
        XCTAssertEqual(item.sourceHint, ".agents/skills/ux-review/SKILL.md")
        XCTAssertEqual(
            item.content.trimmingCharacters(in: .whitespacesAndNewlines),
            """
            You are a senior UX/UI designer reviewing the Zion macOS Git client.

            Read `.claude/commands/documenter.md` when the review also affects docs.
            """
        )
    }

    func testPreviewSyncToClaudeIgnoresCodexFormattingOnlyChanges() throws {
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent(".claude/commands"), withIntermediateDirectories: true)
        try """
        You are a senior UX/UI designer reviewing the Zion macOS Git client.

        Read `.claude/commands/documenter.md` when the review also affects docs.
        """.write(
            to: tempDir.appendingPathComponent(".claude/commands/ux-review.md"),
            atomically: true,
            encoding: .utf8
        )

        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent(".agents/skills/ux-review"), withIntermediateDirectories: true)
        try """
        ---
        name: ux-review
        description: Review Zion UX/UI and propose concrete SwiftUI improvements with code-level guidance.
        ---

        # UX Review

        Mirror and execute the workflow defined for Claude command parity using Codex skills.

        ## Workflow
        You are a senior UX/UI designer reviewing the Zion macOS Git client.

        Read `.agents/skills/documenter/SKILL.md` when the review also affects docs.
        """.write(
            to: tempDir.appendingPathComponent(".agents/skills/ux-review/SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        _ = try service.importConfiguration(from: .codex, repositoryURL: tempDir)
        let preview = try service.previewSync(to: .claude, repositoryURL: tempDir)
        let operation = try XCTUnwrap(preview.operations.first { $0.relativePath == ".claude/commands/ux-review.md" })

        XCTAssertEqual(operation.compatibility, .native)
        XCTAssertEqual(operation.kind, .noop)
    }
}
