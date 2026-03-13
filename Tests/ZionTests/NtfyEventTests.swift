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
        XCTAssertEqual(gitOps.count, 2, "Expected 2 gitOps events")
    }

    func testAIGroupCount() {
        let ai = NtfyEvent.allCases.filter { $0.group == .ai }
        XCTAssertEqual(ai.count, 1, "Expected 1 AI event")
    }

    func testGitHubGroupCount() {
        let github = NtfyEvent.allCases.filter { $0.group == .github }
        XCTAssertEqual(github.count, 2, "Expected 2 GitHub events")
    }

    func testMobileRemoteGroupCount() {
        let mobileRemote = NtfyEvent.allCases.filter { $0.group == .mobileRemote }
        XCTAssertEqual(mobileRemote.count, 1, "Expected 1 mobile remote event")
    }

    func testUniqueRawValues() {
        let rawValues = NtfyEvent.allCases.map(\.rawValue)
        XCTAssertEqual(Set(rawValues).count, rawValues.count, "Duplicate raw values found")
    }

    func testCaseCountGuard() {
        // If a new event is added, this test reminds you to update the test suite
        XCTAssertEqual(NtfyEvent.allCases.count, 6, "Event count changed — update tests")
    }

    func testDefaultEnabledEventsMatchEnabledByDefault() {
        let fromDefaultEnabled = NtfyEvent.defaultEnabledEvents.sorted()
        let fromProperty = NtfyEvent.allCases.filter(\.enabledByDefault).map(\.rawValue).sorted()
        XCTAssertEqual(fromDefaultEnabled, fromProperty)
    }

    func testTerminalPromptDetectedIsNotEnabledByDefault() {
        XCTAssertFalse(NtfyEvent.terminalPromptDetected.enabledByDefault)
        XCTAssertFalse(NtfyEvent.defaultEnabledEvents.contains(NtfyEvent.terminalPromptDetected.rawValue))
    }

    func testGroupCaseCountGuard() {
        XCTAssertEqual(NtfyEventGroup.allCases.count, 4, "Event group count changed — update tests")
    }
}
