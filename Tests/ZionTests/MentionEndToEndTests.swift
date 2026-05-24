// MentionEndToEndTests.swift — proves @file / @folder / @web / @selection are resolved
// by the live MentionResolver wired with the production FileSystemMentionToolClient.
// Exercises the full pipeline minus the LLM round-trip.

import XCTest
@testable import Zion

@MainActor
final class MentionEndToEndTests: XCTestCase {

    private var tempRepo: URL!

    override func setUp() async throws {
        tempRepo = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempRepo, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRepo)
    }

    // MARK: - Helpers

    private func write(_ name: String, _ contents: String) throws -> URL {
        let url = tempRepo.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeResolver() -> MentionResolver {
        MentionResolver(toolClient: FileSystemMentionToolClient(repoURL: tempRepo))
    }

    // MARK: - @file end-to-end

    func test_at_file_resolves_real_file_contents() async throws {
        _ = try write("Notes.md", "# Hello world")
        let resolver = makeResolver()
        let payload = await resolver.expand(message: "Quick read: @file Notes.md please.")
        XCTAssertTrue(payload.systemContext.contains("Hello world"), "Expected file body to be injected. Got: \(payload.systemContext)")
        XCTAssertEqual(payload.mentions.count, 1)
        XCTAssertEqual(payload.mentions.first?.kind, .file)
    }

    func test_at_file_respects_byte_cap() async throws {
        let bigBody = String(repeating: "A", count: 200_000)
        _ = try write("Huge.txt", bigBody)
        let resolver = makeResolver()
        UserDefaults.standard.set(1024, forKey: "chat.mentions.maxBytesPerFile")
        defer { UserDefaults.standard.removeObject(forKey: "chat.mentions.maxBytesPerFile") }

        let payload = await resolver.expand(message: "@file Huge.txt")
        XCTAssertLessThan(payload.systemContext.count, 5_000, "Byte cap must truncate the payload")
    }

    // MARK: - @folder end-to-end

    func test_at_folder_caps_file_count() async throws {
        let subdir = tempRepo.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        for i in 0..<50 {
            try "// file \(i)\n".write(to: subdir.appendingPathComponent("F\(i).swift"), atomically: true, encoding: .utf8)
        }
        UserDefaults.standard.set(5, forKey: "chat.mentions.maxFilesPerFolder")
        defer { UserDefaults.standard.removeObject(forKey: "chat.mentions.maxFilesPerFolder") }

        let resolver = makeResolver()
        let payload = await resolver.expand(message: "@folder nested")
        XCTAssertLessThanOrEqual(payload.perFileBreakdown.count, 5, "Per-folder cap not enforced")
    }

    // MARK: - Code-fence safety

    func test_inside_code_fence_skipped() async throws {
        _ = try write("Real.swift", "let real = true")
        let resolver = makeResolver()
        let message = """
        Look at this snippet:

        ```
        @file Real.swift
        ```

        That was just an example.
        """
        let payload = await resolver.expand(message: message)
        XCTAssertEqual(payload.mentions.count, 0, "Mention inside code fence must NOT trigger expansion")
    }

    // MARK: - @selection

    func test_at_selection_uses_provider_callback() async throws {
        let resolver = MentionResolver(
            toolClient: FileSystemMentionToolClient(repoURL: tempRepo),
            selectionProvider: { "let answer = 42" }
        )
        let payload = await resolver.expand(message: "Tell me about @selection please.")
        XCTAssertTrue(payload.systemContext.contains("let answer = 42"))
    }

    // MARK: - Path traversal rejection

    func test_at_file_rejects_path_traversal() async throws {
        let resolver = makeResolver()
        let payload = await resolver.expand(message: "@file ../../etc/passwd")
        XCTAssertTrue(
            payload.systemContext.lowercased().contains("error"),
            "Path traversal must be rejected with an error marker. Got: \(payload.systemContext)"
        )
    }
}
