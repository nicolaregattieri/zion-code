import XCTest
@testable import Zion

@MainActor
final class TerminalSessionTests: XCTestCase {
    func testKillCachedProcessClearsCachedState() {
        let session = TerminalSession(
            workingDirectory: URL(fileURLWithPath: "/tmp/repo"),
            label: "main"
        )
        session._cachedView = NSObject()
        session._cachedTerminal = NSObject()
        session._processBridge = NSObject()
        session._activeCoordinatorGeneration = UUID()
        session._shellPid = 0

        session.killCachedProcess()

        XCTAssertFalse(session._shouldPreserve)
        XCTAssertNil(session._cachedView)
        XCTAssertNil(session._cachedTerminal)
        XCTAssertNil(session._processBridge)
        XCTAssertNil(session._activeCoordinatorGeneration)
        XCTAssertEqual(session._shellPid, 0)
    }

    func testKillCachedProcessIsIdempotent() {
        let session = TerminalSession(
            workingDirectory: URL(fileURLWithPath: "/tmp/repo"),
            label: "main"
        )

        session.killCachedProcess()
        session.killCachedProcess()

        XCTAssertFalse(session._shouldPreserve)
        XCTAssertNil(session._cachedView)
        XCTAssertNil(session._cachedTerminal)
        XCTAssertNil(session._processBridge)
        XCTAssertNil(session._activeCoordinatorGeneration)
        XCTAssertEqual(session._shellPid, 0)
    }
}
