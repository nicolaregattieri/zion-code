import XCTest
@testable import Zion

/// Verifies that session/project selection persists across page refreshes
/// via sessionStorage, and that refreshScreen fires for empty buffers
/// so the terminal content loads after a page reload.
final class MobileWebClientSelectSessionTests: XCTestCase {

    private lazy var html: String = MobileWebClient.html

    // MARK: - Session Persistence

    func testActiveSessionRestoredFromSessionStorage() {
        XCTAssertTrue(
            html.contains("sessionStorage.getItem('zion_activeSession')"),
            "activeSession should be restored from sessionStorage on load"
        )
    }

    func testActiveProjectRestoredFromSessionStorage() {
        XCTAssertTrue(
            html.contains("sessionStorage.getItem('zion_activeProject')"),
            "activeProject should be restored from sessionStorage on load"
        )
    }

    func testSelectSessionSavesToSessionStorage() {
        XCTAssertTrue(
            html.contains("sessionStorage.setItem('zion_activeSession', id)"),
            "selectSession should save activeSession to sessionStorage"
        )
        XCTAssertTrue(
            html.contains("sessionStorage.setItem('zion_activeProject', activeProject)"),
            "selectSession should save activeProject to sessionStorage"
        )
    }

    // MARK: - Restored Session Re-selected

    func testRestoredSessionReselectedOnSessionList() {
        XCTAssertTrue(
            html.contains("selectSession(activeSession)"),
            "Valid persisted session should be re-selected on sessionList"
        )
    }

    // MARK: - refreshScreen on Empty Buffer

    func testRefreshScreenFiresOnEmptyBuffer() {
        let jsSection = html.components(separatedBy: "function selectSession(id)")
            .last ?? ""
        let functionBody = String(jsSection.prefix(600))

        XCTAssertTrue(
            functionBody.contains("chunks.length === 0"),
            "refreshScreen should fire when buffer is empty"
        )
        XCTAssertTrue(
            functionBody.contains("sendAction('refreshScreen')"),
            "refreshScreen action should be sent to the server"
        )
    }
}
