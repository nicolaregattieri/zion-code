import XCTest
@testable import Zion

@MainActor
final class RepositoryViewModelTerminalTests: XCTestCase {

    // MARK: - createTerminalSession

    func testCreateTerminalSessionAppendsTab() {
        let vm = RepositoryViewModel()
        let dir = URL(fileURLWithPath: "/tmp/repo")
        XCTAssertTrue(vm.terminalTabs.isEmpty)

        vm.createTerminalSession(workingDirectory: dir, label: "main")

        XCTAssertEqual(vm.terminalTabs.count, 1)
        XCTAssertNotNil(vm.activeTabID)
        XCTAssertNotNil(vm.focusedSessionID)
    }

    func testCreateTerminalSessionSetsActiveAndFocused() {
        let vm = RepositoryViewModel()
        let dir = URL(fileURLWithPath: "/tmp/repo")

        vm.createTerminalSession(workingDirectory: dir, label: "main")

        let session = vm.terminalSessions.first
        XCTAssertNotNil(session)
        XCTAssertEqual(vm.focusedSessionID, session?.id)
        XCTAssertEqual(vm.activeTabID, vm.terminalTabs.first?.id)
    }

    func testCreateTerminalSessionWithWorktreeIDReusesExisting() {
        let vm = RepositoryViewModel()
        let dir = URL(fileURLWithPath: "/tmp/repo")

        vm.createTerminalSession(workingDirectory: dir, label: "wt-1", worktreeID: "wt-path")
        let countAfterFirst = vm.terminalTabs.count

        vm.createTerminalSession(workingDirectory: dir, label: "wt-1", worktreeID: "wt-path")

        XCTAssertEqual(vm.terminalTabs.count, countAfterFirst,
                        "Should reuse existing session for same worktreeID")
    }

    func testCreateTerminalSessionActivateFalse() {
        let vm = RepositoryViewModel()
        let dir = URL(fileURLWithPath: "/tmp/repo")

        vm.createTerminalSession(workingDirectory: dir, label: "bg", activate: false)

        XCTAssertEqual(vm.terminalTabs.count, 1)
        XCTAssertNil(vm.activeTabID, "Should not activate when activate=false")
        XCTAssertNil(vm.focusedSessionID, "Should not focus when activate=false")
    }

    // MARK: - closeTab

    func testCloseTabRemovesTab() {
        let vm = RepositoryViewModel()
        let dir = URL(fileURLWithPath: "/tmp/repo")
        vm.createTerminalSession(workingDirectory: dir, label: "main")
        XCTAssertEqual(vm.terminalTabs.count, 1)

        let tab = vm.terminalTabs[0]
        vm.closeTab(tab)

        XCTAssertTrue(vm.terminalTabs.isEmpty)
    }

    func testCloseTabUpdatesActiveTabID() {
        let vm = RepositoryViewModel()
        let dir = URL(fileURLWithPath: "/tmp/repo")

        vm.createTerminalSession(workingDirectory: dir, label: "first")
        vm.createTerminalSession(workingDirectory: dir, label: "second")

        let secondTab = vm.terminalTabs[1]
        vm.activeTabID = secondTab.id

        vm.closeTab(secondTab)

        XCTAssertEqual(vm.terminalTabs.count, 1)
        XCTAssertEqual(vm.activeTabID, vm.terminalTabs.last?.id)
    }

    func testCloseTabFallbackToLastRemaining() {
        let vm = RepositoryViewModel()
        let dir = URL(fileURLWithPath: "/tmp/repo")

        vm.createTerminalSession(workingDirectory: dir, label: "first")
        vm.createTerminalSession(workingDirectory: dir, label: "second")

        let firstTab = vm.terminalTabs[0]
        vm.activeTabID = firstTab.id

        vm.closeTab(firstTab)

        XCTAssertEqual(vm.terminalTabs.count, 1)
        // activeTabID was the closed tab, so it should fall back
        // (closeTab only updates if activeTabID == tab.id)
    }

    // MARK: - activateSession

    func testActivateSessionSetsActiveAndFocused() {
        let vm = RepositoryViewModel()
        let dir = URL(fileURLWithPath: "/tmp/repo")

        vm.createTerminalSession(workingDirectory: dir, label: "first")
        vm.createTerminalSession(workingDirectory: dir, label: "second")

        let firstSession = vm.terminalTabs[0].allSessions().first!
        let secondSession = vm.terminalTabs[1].allSessions().first!

        // Activate first session (second is currently active)
        vm.activateSession(firstSession)

        XCTAssertEqual(vm.focusedSessionID, firstSession.id)
        XCTAssertEqual(vm.activeTabID, vm.terminalTabs[0].id)

        // Activate second session
        vm.activateSession(secondSession)

        XCTAssertEqual(vm.focusedSessionID, secondSession.id)
        XCTAssertEqual(vm.activeTabID, vm.terminalTabs[1].id)
    }

    // MARK: - createDefaultTerminalSession

    func testCreateDefaultTerminalSessionCreatesNew() {
        let vm = RepositoryViewModel()
        let dir = URL(fileURLWithPath: "/tmp/repo")

        vm.createDefaultTerminalSession(repositoryURL: dir, branchName: "main")

        XCTAssertEqual(vm.terminalTabs.count, 1)
        let session = vm.terminalSessions.first
        XCTAssertEqual(session?.label, "main")
        XCTAssertEqual(session?.workingDirectory.path, dir.path)
    }

    func testCreateDefaultTerminalSessionReusesExistingForSameDir() {
        let vm = RepositoryViewModel()
        let dir = URL(fileURLWithPath: "/tmp/repo")

        vm.createDefaultTerminalSession(repositoryURL: dir, branchName: "main")
        let initialCount = vm.terminalTabs.count

        vm.createDefaultTerminalSession(repositoryURL: dir, branchName: "feature")

        XCTAssertEqual(vm.terminalTabs.count, initialCount,
                        "Should reuse session for same working directory")
    }

    func testCreateDefaultTerminalSessionNilRepoUsesHome() {
        let vm = RepositoryViewModel()
        let homePath = NSHomeDirectory()

        vm.createDefaultTerminalSession(repositoryURL: nil, branchName: "detached")

        let session = vm.terminalSessions.first
        XCTAssertEqual(session?.workingDirectory.path, homePath)
    }

    // MARK: - targeted terminal send routing

    func testSendTextToTerminalRoutesToProvidedSession() {
        let vm = RepositoryViewModel()
        let dir = URL(fileURLWithPath: "/tmp/repo")

        vm.createTerminalSession(workingDirectory: dir, label: "first")
        vm.createTerminalSession(workingDirectory: dir, label: "second")

        let first = vm.terminalTabs[0].allSessions().first!
        let second = vm.terminalTabs[1].allSessions().first!
        var firstReceived: String?
        var secondReceived: String?

        vm.registerTerminalSendCallback(sessionID: first.id) { data in
            firstReceived = String(data: data, encoding: .utf8)
        }
        vm.registerTerminalSendCallback(sessionID: second.id) { data in
            secondReceived = String(data: data, encoding: .utf8)
        }

        vm.sendTextToTerminal("echo pane-1", sessionID: first.id)

        XCTAssertEqual(firstReceived, "echo pane-1")
        XCTAssertNil(secondReceived)
        XCTAssertEqual(vm.focusedSessionID, first.id)
    }

    func testSendTextToTerminalWithoutCallbackDoesNothing() {
        let vm = RepositoryViewModel()
        let dir = URL(fileURLWithPath: "/tmp/repo")
        vm.createTerminalSession(workingDirectory: dir, label: "first")
        let first = vm.terminalTabs[0].allSessions().first!

        vm.sendTextToTerminal("echo ignored", sessionID: first.id)

        XCTAssertEqual(vm.focusedSessionID, first.id)
    }

    // MARK: - splitFocusedTerminal

    func testSplitHorizontalDividesFocusedPaneInHalf() {
        let vm = RepositoryViewModel()
        let dir = URL(fileURLWithPath: "/tmp/repo")
        vm.createTerminalSession(workingDirectory: dir, label: "main")

        vm.splitFocusedTerminal(direction: .horizontal)

        let tab = vm.terminalTabs[0]
        guard case .split(let direction, _, _) = tab.content else {
            return XCTFail("Expected split content")
        }
        XCTAssertEqual(direction, .horizontal)
        XCTAssertEqual(tab.ratio, 0.5, accuracy: 0.001,
                       "First split should always be 50/50")
    }

    func testSplitDoesNotRedistributeSiblingRatios() {
        let vm = RepositoryViewModel()
        let dir = URL(fileURLWithPath: "/tmp/repo")

        // Create an initial session and split it horizontally
        vm.createTerminalSession(workingDirectory: dir, label: "first")
        vm.splitFocusedTerminal(direction: .horizontal)

        let tab = vm.terminalTabs[0]
        // Manually resize: give the first pane 70% of space
        tab.ratio = 0.7

        // Now focus the second pane (the new one created by split) and split it again
        let secondSession = tab.allSessions().last!
        vm.focusedSessionID = secondSession.id
        vm.splitFocusedTerminal(direction: .horizontal)

        // The top-level ratio should still be 0.7 — sibling was not touched
        XCTAssertEqual(tab.ratio, 0.7, accuracy: 0.001,
                       "Sibling pane ratio must not be redistributed when splitting the focused pane")
    }

    func testSplitVerticalDividesFocusedPaneInHalf() {
        let vm = RepositoryViewModel()
        let dir = URL(fileURLWithPath: "/tmp/repo")
        vm.createTerminalSession(workingDirectory: dir, label: "main")

        vm.splitFocusedTerminal(direction: .vertical)

        let tab = vm.terminalTabs[0]
        guard case .split(let direction, _, _) = tab.content else {
            return XCTFail("Expected split content")
        }
        XCTAssertEqual(direction, .vertical)
        XCTAssertEqual(tab.ratio, 0.5, accuracy: 0.001)
    }

    func testSplitFocusesNewPane() {
        let vm = RepositoryViewModel()
        let dir = URL(fileURLWithPath: "/tmp/repo")
        vm.createTerminalSession(workingDirectory: dir, label: "main")
        let originalID = vm.focusedSessionID

        vm.splitFocusedTerminal(direction: .horizontal)

        XCTAssertNotEqual(vm.focusedSessionID, originalID,
                          "Focus should move to the newly created pane")
    }
}
