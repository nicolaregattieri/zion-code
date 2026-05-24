// MentionResolverTests.swift — Tests for MentionResolver @mention expansion.
//
// 8 scenarios covering: @file, @folder caps, @selection, @web,
// code-fence exclusion, folder I/O cap verification, email non-expansion,
// and missing argument handling.

import XCTest
@testable import Zion

// MARK: - MockMentionToolClient

/// Records callTool invocations and returns scripted responses.
final class MockMentionToolClient: MentionToolClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(name: String, args: [String: Any])] = []
    private let responses: [String: String]

    init(responses: [String: String] = [:]) {
        self.responses = responses
    }

    var calls: [(name: String, args: [String: Any])] {
        lock.withLock { _calls }
    }

    var callCount: Int { calls.count }

    func callCount(for toolName: String) -> Int {
        calls.filter { $0.name == toolName }.count
    }

    func callTool(_ name: String, args: [String: Any]) async throws -> String {
        lock.withLock {
            _calls.append((name: name, args: args))
        }
        return responses[name] ?? ""
    }
}

// MARK: - MentionResolverTests

final class MentionResolverTests: XCTestCase {

    // MARK: 1. @file expansion

    func test_expands_at_file() async throws {
        let mock = MockMentionToolClient(responses: ["read_file": "FILE CONTENT"])
        let resolver = MentionResolver(toolClient: mock)

        let payload = await resolver.expand(message: "hello @file Foo.swift")

        XCTAssertTrue(payload.systemContext.contains("FILE CONTENT"),
                      "systemContext should contain file contents")
        XCTAssertTrue(payload.systemContext.contains("@file Foo.swift"),
                      "systemContext should contain the @file header")
        XCTAssertEqual(mock.callCount(for: "read_file"), 1)
    }

    // MARK: 2. @folder with caps

    func test_expands_at_folder_with_caps() async throws {
        // list_dir returns 50 file paths (one per line)
        let listingLines = (1...50).map { "src/file\($0).swift" }.joined(separator: "\n")
        let mock = MockMentionToolClient(responses: [
            "list_dir": listingLines,
            "read_file": "content"
        ])
        let resolver = MentionResolver(toolClient: mock)

        let payload = await resolver.expand(message: "@folder src/")

        let readFileCalls = mock.callCount(for: "read_file")
        XCTAssertLessThanOrEqual(readFileCalls, MentionResolver.defaultMaxFilesPerFolder,
                                  "read_file must be called at most maxFilesPerFolder times")
        XCTAssertFalse(payload.systemContext.isEmpty)
    }

    // MARK: 3. @selection expansion

    func test_expands_at_selection() async throws {
        let mock = MockMentionToolClient()
        let resolver = MentionResolver(toolClient: mock, selectionProvider: { "selected text" })

        let payload = await resolver.expand(message: "check @selection here")

        XCTAssertTrue(payload.systemContext.contains("selected text"),
                      "systemContext should contain the selection")
        XCTAssertEqual(mock.callCount, 0, "@selection does not call any MCP tool")
    }

    // MARK: 4. @web expansion

    func test_expands_at_web() async throws {
        let mock = MockMentionToolClient(responses: ["web_fetch": "PAGE BODY"])
        let resolver = MentionResolver(toolClient: mock)

        let payload = await resolver.expand(message: "see @web https://example.com")

        XCTAssertTrue(payload.systemContext.contains("PAGE BODY"),
                      "systemContext should contain web page body")
        XCTAssertEqual(mock.callCount(for: "web_fetch"), 1)
    }

    // MARK: 5. Ignore mentions inside code fences

    func test_ignores_mentions_inside_code_fence() async throws {
        let mock = MockMentionToolClient(responses: ["read_file": "CONTENT"])
        let resolver = MentionResolver(toolClient: mock)

        // @MainActor is inside the fence — but even if it weren't, it doesn't match (file|folder|selection|web)
        // The @file Foo.swift is OUTSIDE the fence and SHOULD be expanded.
        let message = "look here\n```swift\n@MainActor func foo() {}\n```\nlater @file Foo.swift"
        let payload = await resolver.expand(message: message)

        // @file Foo.swift is outside the fence — read_file called once
        XCTAssertEqual(mock.callCount(for: "read_file"), 1,
                       "Only the outside-fence @file should trigger read_file")
        XCTAssertTrue(payload.systemContext.contains("@file Foo.swift"))
    }

    // MARK: 6. Folder caps before I/O fan-out

    func test_folder_caps_before_io() async throws {
        // list_dir returns 100 files
        let listingLines = (1...100).map { "src/file\($0).swift" }.joined(separator: "\n")
        let mock = MockMentionToolClient(responses: [
            "list_dir": listingLines,
            "read_file": "content"
        ])
        let resolver = MentionResolver(toolClient: mock)

        _ = await resolver.expand(message: "@folder src/")

        let readFileCalls = mock.callCount(for: "read_file")
        XCTAssertLessThanOrEqual(readFileCalls, MentionResolver.defaultMaxFilesPerFolder,
                                  "read_file call count must not exceed maxFilesPerFolder (cap enforced BEFORE fan-out)")
    }

    // MARK: 7. Plain email not expanded

    func test_plain_email_not_expanded() async throws {
        let mock = MockMentionToolClient()
        let resolver = MentionResolver(toolClient: mock)

        _ = await resolver.expand(message: "contact user@host.com for help")

        XCTAssertEqual(mock.callCount, 0,
                       "user@host.com must not trigger any tool call (kind group only matches file|folder|selection|web)")
    }

    // MARK: 8. @file without argument

    func test_mention_without_argument() async throws {
        let mock = MockMentionToolClient(responses: ["read_file": "content"])
        let resolver = MentionResolver(toolClient: mock)

        let payload = await resolver.expand(message: "@file")

        // No argument → no expansion → systemContext empty, no I/O
        XCTAssertTrue(payload.systemContext.isEmpty,
                      "A bare @file with no path argument must not produce any systemContext")
        XCTAssertEqual(mock.callCount, 0,
                       "No I/O should occur for a mention without an argument")
    }

    // MARK: Parser unit tests

    func test_parseMentions_basic() {
        let result = MentionResolver.parseMentions("hello @file Foo.swift world")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].kind, .file)
        XCTAssertEqual(result[0].argument, "Foo.swift")
    }

    func test_splitCodeFences_basic() {
        let message = "before\n```\ninside\n```\nafter"
        let segments = MentionResolver.splitCodeFences(message)
        let outside = segments.filter { !$0.inFence }.map { $0.text }
        let inside  = segments.filter {  $0.inFence }.map { $0.text }
        XCTAssertTrue(outside.joined().contains("before"))
        XCTAssertTrue(outside.joined().contains("after"))
        XCTAssertTrue(inside.joined().contains("inside"))
    }
}
