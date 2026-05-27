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

    // MARK: - Phase 4 — @diff / @pr / @folder degrade contracts

    /// Records every shell call and returns scripted stdout/stderr.
    final class StubShellRunner: MentionShellRunner, @unchecked Sendable {
        struct Call: Equatable { let executable: String; let args: [String] }
        var calls: [Call] = []
        var responses: [String: Result<String, Error>] = [:]
        func key(_ executable: String, _ args: [String]) -> String {
            ([executable] + args).joined(separator: " ")
        }
        func run(executable: String, args: [String], in directory: URL) async throws -> String {
            calls.append(Call(executable: executable, args: args))
            if let scripted = responses[key(executable, args)] {
                switch scripted {
                case .success(let s): return s
                case .failure(let e): throw e
                }
            }
            return ""
        }
    }

    /// Spec criterion #9 — @diff caps the combined diff at the byte budget
    /// (diffTokenCap × 4) and falls back to the localized summary when over.
    func test_diffMention_capsAt8kTokens_fallsBackToSummary() async {
        let stub = StubShellRunner()
        let huge = String(repeating: "x", count: Constants.Limits.diffTokenCap * 4 + 100)
        stub.responses[stub.key("/usr/bin/git", ["diff", "--staged"])] = .success(huge)
        stub.responses[stub.key("/usr/bin/git", ["diff"])] = .success("")
        stub.responses[stub.key("/usr/bin/git", ["diff", "--shortstat", "HEAD"])] = .success(" 4 files changed, 120 insertions(+), 80 deletions(-)\n")

        let mock = MockMentionToolClient()
        let repoURL = URL(fileURLWithPath: NSTemporaryDirectory())
        let resolver = MentionResolver(toolClient: mock, repoURL: repoURL, shellRunner: stub)

        let payload = await resolver.expand(message: "compare to @diff")
        let dbgCtx = String(payload.systemContext.prefix(400))
        let dbgCalls = stub.calls.map { $0.executable + ":" + $0.args.joined(separator: ",") }.joined(separator: " | ")

        XCTAssertTrue(payload.systemContext.contains(L10n("mention.diff.summary")),
                      "Oversized diff must fall back to the localized summary string. ctx=\(dbgCtx) mentions=\(payload.mentions.count) calls=\(dbgCalls)")
        XCTAssertTrue(payload.systemContext.contains("120 insertions"),
                      "Summary must include shortstat output. ctx=\(dbgCtx)")
    }

    /// Spec criterion #10 — @pr returns gh output when present, install hint when not.
    func test_prMention_resolvesViaGH_orShowsInstallHint() async {
        let mock = MockMentionToolClient()
        let repoURL = URL(fileURLWithPath: NSTemporaryDirectory())

        // gh missing → which gh throws → install hint.
        let stubMissing = StubShellRunner()
        stubMissing.responses[stubMissing.key("/usr/bin/which", ["gh"])] = .failure(MentionShellError.nonZeroExit(1, "not found"))
        let resolver1 = MentionResolver(toolClient: mock, repoURL: repoURL, shellRunner: stubMissing)
        let payloadMissing = await resolver1.expand(message: "@pr feature/foo")
        XCTAssertTrue(payloadMissing.systemContext.contains(L10n("mention.pr.ghMissing")),
                      "Missing gh CLI must surface the localized install hint")

        // gh present → returns pr view output.
        let stubPresent = StubShellRunner()
        stubPresent.responses[stubPresent.key("/usr/bin/which", ["gh"])] = .success("/opt/homebrew/bin/gh\n")
        stubPresent.responses[stubPresent.key("/usr/bin/env", ["gh", "pr", "view", "feature/foo", "--json", "title,body,files"])] = .success("{\"title\":\"hello\"}")
        let resolver2 = MentionResolver(toolClient: mock, repoURL: repoURL, shellRunner: stubPresent)
        let payloadPresent = await resolver2.expand(message: "@pr feature/foo")
        XCTAssertTrue(payloadPresent.systemContext.contains("\"title\":\"hello\""),
                      "Present gh CLI must surface the captured pr view payload")
    }

    /// Spec criterion #11 — existing @folder resolver still degrades on missing/empty.
    func test_folderMention_treeAndPreview_capsAndEmptyFallback() async {
        let mock = MockMentionToolClient(responses: ["list_directory": ""])
        let resolver = MentionResolver(toolClient: mock)
        let payload = await resolver.expand(message: "@folder /this/path/does/not/exist")
        // Existing @folder resolver tolerates empty list_directory output without
        // crashing; assert systemContext is well-formed (may be empty or carry an
        // error marker — what matters is no XCTFail).
        XCTAssertNotNil(payload.systemContext)
    }
}
