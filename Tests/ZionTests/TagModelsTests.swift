import XCTest
@testable import Zion

final class TagModelsTests: XCTestCase {

    // MARK: - TagType

    func testTagTypeCases() {
        XCTAssertEqual(TagType.allCases.count, 3)
        XCTAssertEqual(TagType.lightweight.rawValue, "lightweight")
        XCTAssertEqual(TagType.annotated.rawValue, "annotated")
        XCTAssertEqual(TagType.signed.rawValue, "signed")
    }

    func testTagTypeLabels() {
        XCTAssertFalse(TagType.lightweight.label.isEmpty)
        XCTAssertFalse(TagType.annotated.label.isEmpty)
        XCTAssertFalse(TagType.signed.label.isEmpty)
    }

    func testTagTypeIdentifiable() {
        XCTAssertEqual(TagType.lightweight.id, "lightweight")
        XCTAssertEqual(TagType.annotated.id, "annotated")
        XCTAssertEqual(TagType.signed.id, "signed")
    }

    // MARK: - TagInfo

    func testTagInfoIdentifiable() {
        let tag = TagInfo(
            name: "v1.0.0",
            type: .annotated,
            message: "Release 1.0.0",
            tagger: "dev <dev@example.com>",
            date: Date()
        )
        XCTAssertEqual(tag.id, "v1.0.0")
        XCTAssertEqual(tag.name, "v1.0.0")
        XCTAssertEqual(tag.type, .annotated)
        XCTAssertEqual(tag.message, "Release 1.0.0")
    }

    func testTagInfoLightweight() {
        let tag = TagInfo(
            name: "v0.1.0",
            type: .lightweight,
            message: "",
            tagger: "",
            date: nil
        )
        XCTAssertEqual(tag.type, .lightweight)
        XCTAssertTrue(tag.message.isEmpty)
        XCTAssertNil(tag.date)
    }

    func testTagInfoSigned() {
        let tag = TagInfo(
            name: "v2.0.0",
            type: .signed,
            message: "Signed release",
            tagger: "signer <signer@example.com>",
            date: Date()
        )
        XCTAssertEqual(tag.type, .signed)
        XCTAssertEqual(tag.message, "Signed release")
    }

    // MARK: - Annotated Tag Git Integration

    func testCreateAnnotatedTag() async throws {
        let repoURL = try GitTestHelper.makeTempRepo()
        defer { GitTestHelper.cleanup(repoURL) }

        // Create an annotated tag
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "tag", "-a", "v1.0.0", "-m", "First release"]
        process.currentDirectoryURL = repoURL
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        // Verify with git show
        let showProcess = Process()
        showProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        showProcess.arguments = ["git", "tag", "-l", "--format", "%(objecttype)"]
        showProcess.currentDirectoryURL = repoURL
        let pipe = Pipe()
        showProcess.standardOutput = pipe
        showProcess.standardError = Pipe()
        try showProcess.run()
        showProcess.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(output.contains("tag"), "Annotated tag should have objecttype 'tag'")
    }

    func testCreateLightweightTag() async throws {
        let repoURL = try GitTestHelper.makeTempRepo()
        defer { GitTestHelper.cleanup(repoURL) }

        // Create a lightweight tag
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "tag", "v0.1.0"]
        process.currentDirectoryURL = repoURL
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        // Verify with git tag
        let tagProcess = Process()
        tagProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        tagProcess.arguments = ["git", "tag", "-l", "--format", "%(objecttype)"]
        tagProcess.currentDirectoryURL = repoURL
        let pipe = Pipe()
        tagProcess.standardOutput = pipe
        tagProcess.standardError = Pipe()
        try tagProcess.run()
        tagProcess.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(output.contains("commit"), "Lightweight tag should point directly to a commit")
    }

    func testAnnotatedTagMessage() async throws {
        let repoURL = try GitTestHelper.makeTempRepo()
        defer { GitTestHelper.cleanup(repoURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "tag", "-a", "v2.0.0", "-m", "Second major release"]
        process.currentDirectoryURL = repoURL
        try process.run()
        process.waitUntilExit()

        // Verify message
        let showProcess = Process()
        showProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        showProcess.arguments = ["git", "tag", "-l", "v2.0.0", "-n1"]
        showProcess.currentDirectoryURL = repoURL
        let pipe = Pipe()
        showProcess.standardOutput = pipe
        showProcess.standardError = Pipe()
        try showProcess.run()
        showProcess.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(output.contains("Second major release"))
    }
}
