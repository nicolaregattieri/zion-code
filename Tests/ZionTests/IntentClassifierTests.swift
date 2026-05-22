import XCTest
@testable import Zion

final class IntentClassifierTests: XCTestCase {

    // MARK: lastCommit

    func test_lastCommit_EN() {
        XCTAssertEqual(IntentClassifier.classify("show me the last commit code"), .lastCommit)
    }

    func test_lastCommit_EN_latest() {
        XCTAssertEqual(IntentClassifier.classify("show me the latest commit"), .lastCommit)
    }

    func test_lastCommit_PTBR() {
        XCTAssertEqual(IntentClassifier.classify("me mostra o ultimo commit"), .lastCommit)
    }

    func test_lastCommit_whatWasCommitted() {
        XCTAssertEqual(IntentClassifier.classify("what was committed?"), .lastCommit)
    }

    // MARK: currentChanges

    func test_currentChanges_EN() {
        XCTAssertEqual(IntentClassifier.classify("what changed?"), .currentChanges)
    }

    func test_currentChanges_PTBR() {
        XCTAssertEqual(IntentClassifier.classify("que mudou no working tree"), .currentChanges)
    }

    func test_currentChanges_unstaged() {
        XCTAssertEqual(IntentClassifier.classify("show unstaged files"), .currentChanges)
    }

    func test_currentChanges_myChanges() {
        XCTAssertEqual(IntentClassifier.classify("show my changes"), .currentChanges)
    }

    // MARK: recentHistory

    func test_recentHistory_EN() {
        XCTAssertEqual(IntentClassifier.classify("show recent history"), .recentHistory)
    }

    func test_recentHistory_PTBR() {
        XCTAssertEqual(IntentClassifier.classify("mostra historico"), .recentHistory)
    }

    func test_recentHistory_gitLog() {
        XCTAssertEqual(IntentClassifier.classify("git log"), .recentHistory)
    }

    func test_recentHistory_recentCommits() {
        XCTAssertEqual(IntentClassifier.classify("show recent commits"), .recentHistory)
    }

    // MARK: status

    func test_status_EN() {
        XCTAssertEqual(IntentClassifier.classify("what's the repo status"), .status)
    }

    func test_status_PTBR() {
        XCTAssertEqual(IntentClassifier.classify("estado do repo"), .status)
    }

    func test_status_staged() {
        XCTAssertEqual(IntentClassifier.classify("what's staged"), .status)
    }

    func test_status_workingTreeState() {
        XCTAssertEqual(IntentClassifier.classify("show working tree state"), .status)
    }

    // MARK: fileContent

    func test_fileContent_show() {
        XCTAssertEqual(IntentClassifier.classify("show src/Foo.swift"), .fileContent(path: "src/Foo.swift"))
    }

    func test_fileContent_review() {
        XCTAssertEqual(IntentClassifier.classify("review packages/api/index.ts"), .fileContent(path: "packages/api/index.ts"))
    }

    func test_fileContent_read() {
        XCTAssertEqual(IntentClassifier.classify("read Config.plist"), .fileContent(path: "Config.plist"))
    }

    // MARK: commitDetails

    func test_commitDetails_short() {
        XCTAssertEqual(IntentClassifier.classify("commit abc1234"), .commitDetails(sha: "abc1234"))
    }

    func test_commitDetails_long() {
        XCTAssertEqual(IntentClassifier.classify("sha deadbeef0123456"), .commitDetails(sha: "deadbeef0123456"))
    }

    func test_commitDetails_full40() {
        let sha = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        XCTAssertEqual(IntentClassifier.classify("commit \(sha)"), .commitDetails(sha: sha))
    }

    // MARK: nil (conservative — must not false-positive)

    func test_nil_sse() {
        XCTAssertNil(IntentClassifier.classify("what is SSE?"))
    }

    func test_nil_hello() {
        XCTAssertNil(IntentClassifier.classify("hello"))
    }

    func test_nil_explainAsync() {
        XCTAssertNil(IntentClassifier.classify("explain async/await"))
    }

    func test_nil_empty() {
        XCTAssertNil(IntentClassifier.classify(""))
    }

    func test_nil_architecture() {
        XCTAssertNil(IntentClassifier.classify("explain the architecture"))
    }
}
