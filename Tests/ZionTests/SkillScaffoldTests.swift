import XCTest
@testable import Zion

// Tests for SkillIndex.scaffold(name:description:scope:rootOverride:)
@MainActor
final class SkillScaffoldTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkillScaffoldTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Tests

    func test_scaffold_writes_SKILL_md_in_tempRoot() throws {
        let temp = try makeTempDir()
        defer { cleanup(temp) }

        let index = SkillIndex()
        let fileURL = try index.scaffold(
            name: "Test Skill",
            description: "do stuff",
            scope: .project,
            rootOverride: temp
        )

        let expected = temp.appendingPathComponent("test-skill/SKILL.md")
        XCTAssertEqual(fileURL.path, expected.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: expected.path),
                      "SKILL.md should exist at \(expected.path)")
    }

    func test_scaffold_writes_parseable_frontmatter() throws {
        let temp = try makeTempDir()
        defer { cleanup(temp) }

        let index = SkillIndex()
        let fileURL = try index.scaffold(
            name: "Test Skill",
            description: "do stuff",
            scope: .project,
            rootOverride: temp
        )

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let (frontmatter, _) = SkillIndex.parseFrontmatter(content: content)

        XCTAssertEqual(frontmatter["name"], "test-skill")
        XCTAssertEqual(frontmatter["description"], "do stuff")
    }

    func test_scaffold_invalid_name_throws() throws {
        let temp = try makeTempDir()
        defer { cleanup(temp) }

        let index = SkillIndex()

        // Empty name
        XCTAssertThrowsError(
            try index.scaffold(name: "", description: "desc", scope: .user, rootOverride: temp)
        ) { error in
            XCTAssertEqual(error as? SkillIndex.ScaffoldError, .invalidName)
        }

        // All special chars (filter removes all)
        XCTAssertThrowsError(
            try index.scaffold(name: "!@#$%", description: "desc", scope: .user, rootOverride: temp)
        ) { error in
            XCTAssertEqual(error as? SkillIndex.ScaffoldError, .invalidName)
        }
    }

    func test_scaffold_duplicate_throws() throws {
        let temp = try makeTempDir()
        defer { cleanup(temp) }

        let index = SkillIndex()
        _ = try index.scaffold(
            name: "My Skill",
            description: "first",
            scope: .project,
            rootOverride: temp
        )

        XCTAssertThrowsError(
            try index.scaffold(name: "My Skill", description: "second", scope: .project, rootOverride: temp)
        ) { error in
            XCTAssertEqual(error as? SkillIndex.ScaffoldError, .directoryExists)
        }
    }

    func test_scaffold_slugifies_spaces_and_caps() throws {
        let temp = try makeTempDir()
        defer { cleanup(temp) }

        let index = SkillIndex()
        let fileURL = try index.scaffold(
            name: "My Long Skill!",
            description: "test",
            scope: .project,
            rootOverride: temp
        )

        // "My Long Skill!" → lowercase → "my long skill!" → replace spaces → "my-long-skill!"
        // filter letters/numbers/dashes → "my-long-skill"
        XCTAssertTrue(fileURL.path.contains("my-long-skill/SKILL.md"),
                      "Expected slug 'my-long-skill', got path: \(fileURL.path)")
    }

    func test_scaffold_body_contains_usage_section() throws {
        let temp = try makeTempDir()
        defer { cleanup(temp) }

        let index = SkillIndex()
        let fileURL = try index.scaffold(
            name: "Code Review",
            description: "Review code",
            scope: .user,
            rootOverride: temp
        )

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("/code-review"), "Body should include the slash invocation")
        XCTAssertTrue(content.contains("## Usage"), "Body should include Usage section")
    }
}

// Equatable conformance lives in the Zion module (SkillIndex.swift). Drop the
// `: Equatable` here so Swift 6 doesn't warn about duplicate conformance, but
// keep the explicit == so tests use a test-friendly diff if cases evolve.
extension SkillIndex.ScaffoldError {
    public static func == (lhs: SkillIndex.ScaffoldError, rhs: SkillIndex.ScaffoldError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidName, .invalidName): return true
        case (.directoryExists, .directoryExists): return true
        case (.writeFailed, .writeFailed): return true
        default: return false
        }
    }
}
