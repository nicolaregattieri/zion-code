import XCTest
@testable import Zion

final class NtfyEventTests: XCTestCase {

    func testAllEventsHaveNonEmptyEmojiTag() {
        for event in NtfyEvent.allCases {
            XCTAssertFalse(event.emojiTag.isEmpty, "\(event.rawValue) has empty emojiTag")
        }
    }

    func testAllEventsHavePriorityInRange() {
        for event in NtfyEvent.allCases {
            XCTAssertTrue((1...5).contains(event.priority), "\(event.rawValue) priority \(event.priority) out of range 1-5")
        }
    }

    func testAllEventsHaveGroup() {
        for event in NtfyEvent.allCases {
            // Just accessing .group verifies it doesn't crash (exhaustive switch)
            _ = event.group
        }
    }

    func testGitOpsGroupCount() {
        let gitOps = NtfyEvent.allCases.filter { $0.group == .gitOps }
        XCTAssertEqual(gitOps.count, 4, "Expected 4 gitOps events")
    }

    func testAIGroupCount() {
        let ai = NtfyEvent.allCases.filter { $0.group == .ai }
        // 7 core AI + branchReviewComplete + prAutoReviewComplete = 9
        XCTAssertEqual(ai.count, 9, "Expected 9 AI events")
    }

    func testGitHubGroupCount() {
        let github = NtfyEvent.allCases.filter { $0.group == .github }
        XCTAssertEqual(github.count, 2, "Expected 2 GitHub events")
    }

    func testUniqueRawValues() {
        let rawValues = NtfyEvent.allCases.map(\.rawValue)
        XCTAssertEqual(Set(rawValues).count, rawValues.count, "Duplicate raw values found")
    }

    func testCaseCountGuard() {
        // If a new event is added, this test reminds you to update the test suite
        XCTAssertEqual(NtfyEvent.allCases.count, 15, "Event count changed — update tests")
    }

    func testDefaultEnabledEventsMatchEnabledByDefault() {
        let fromDefaultEnabled = NtfyEvent.defaultEnabledEvents.sorted()
        let fromProperty = NtfyEvent.allCases.filter(\.enabledByDefault).map(\.rawValue).sorted()
        XCTAssertEqual(fromDefaultEnabled, fromProperty)
    }

    func testGroupCaseCountGuard() {
        XCTAssertEqual(NtfyEventGroup.allCases.count, 3, "Event group count changed — update tests")
    }
}
