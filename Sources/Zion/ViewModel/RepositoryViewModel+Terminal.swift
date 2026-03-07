import Foundation
import SwiftUI
@preconcurrency import SwiftTerm

extension RepositoryViewModel {

    // MARK: - Terminal Session Management

    func createTerminalSession(workingDirectory: URL, label: String, worktreeID: String? = nil, activate: Bool = true) {
        if let worktreeID, let existing = terminalSessions.first(where: { $0.worktreeID == worktreeID }) {
            if activate { activateSession(existing) }
            return
        }
        let session = TerminalSession(workingDirectory: workingDirectory, label: label, worktreeID: worktreeID)
        let tab = TerminalPaneNode(session: session)
        terminalTabs.append(tab)
        if activate {
            activeTabID = tab.id
            focusedSessionID = session.id
        }
    }

    func closeTerminalSession(_ session: TerminalSession) {
        // Explicitly kill the closed session's process before restructuring the view tree
        session.killCachedProcess()

        // Try to close within a split first
        for tab in terminalTabs {
            if let (parent, isFirst) = tab.findParent(of: session.id) {
                // Collapse: replace split with the surviving child
                if case .split(_, let first, let second) = parent.content {
                    parent.content = isFirst ? second.content : first.content
                }
                if focusedSessionID == session.id {
                    focusedSessionID = tab.allSessions().first?.id
                }
                return
            }
        }
        // Not in a split — remove the entire tab
        terminalTabs.removeAll(where: { tab in
            if case .terminal(let s) = tab.content { return s.id == session.id }
            return false
        })
        if activeTabID != nil && !terminalTabs.contains(where: { $0.id == activeTabID }) {
            activeTabID = terminalTabs.last?.id
        }
        if focusedSessionID == session.id {
            focusedSessionID = terminalSessions.last?.id
        }
    }

    func closeTab(_ tab: TerminalPaneNode) {
        // Kill all terminal processes in this tab before removing
        for session in tab.allSessions() {
            session.killCachedProcess()
        }
        terminalTabs.removeAll(where: { $0.id == tab.id })
        if activeTabID == tab.id {
            activeTabID = terminalTabs.last?.id
            focusedSessionID = terminalTabs.last?.allSessions().first?.id
        }
    }

    func activateTerminalSession(_ session: TerminalSession) {
        activateSession(session)
    }

    func activateSession(_ session: TerminalSession) {
        // Find which tab contains this session and activate both tab and session
        for tab in terminalTabs {
            if tab.findNode(containing: session.id) != nil {
                activeTabID = tab.id
                focusedSessionID = session.id
                return
            }
        }
    }

    func splitFocusedTerminal(direction: SplitDirection) {
        guard let focusedID = focusedSessionID else { return }
        for tab in terminalTabs {
            if let node = tab.findNode(containing: focusedID) {
                if case .terminal(let session) = node.content {
                    let newSession = TerminalSession(
                        workingDirectory: session.workingDirectory,
                        label: session.label
                    )
                    let firstNode = TerminalPaneNode(session: session)
                    let secondNode = TerminalPaneNode(session: newSession)
                    node.content = .split(direction: direction, first: firstNode, second: secondNode)
                    focusedSessionID = newSession.id
                    return
                }
            }
        }
    }

    func splitFocusedWithSession(_ newSession: TerminalSession, direction: SplitDirection) {
        guard let focusedID = focusedSessionID else {
            let tab = TerminalPaneNode(session: newSession)
            terminalTabs.append(tab)
            activeTabID = tab.id
            focusedSessionID = newSession.id
            return
        }
        for tab in terminalTabs {
            if let node = tab.findNode(containing: focusedID) {
                if case .terminal(let session) = node.content {
                    let firstNode = TerminalPaneNode(session: session)
                    let secondNode = TerminalPaneNode(session: newSession)
                    node.content = .split(direction: direction, first: firstNode, second: secondNode)
                    focusedSessionID = newSession.id
                    return
                }
            }
        }
        let tab = TerminalPaneNode(session: newSession)
        terminalTabs.append(tab)
        activeTabID = tab.id
        focusedSessionID = newSession.id
    }

    // MARK: - Terminal Helpers

    func closeFocusedTerminalPane() {
        guard let focusedID = focusedSessionID,
              let session = terminalSessions.first(where: { $0.id == focusedID }) else { return }
        closeTerminalSession(session)
    }

    func closeTerminalSession(forWorktree worktreeID: String) {
        if let session = terminalSessions.first(where: { $0.worktreeID == worktreeID }) {
            closeTerminalSession(session)
        }
    }

    func createDefaultTerminalSession(repositoryURL: URL?, branchName: String) {
        let workingDirectory = repositoryURL ?? URL(fileURLWithPath: NSHomeDirectory())

        // If we already have a session for THIS directory, just activate it
        if let existing = terminalSessions.first(where: { $0.workingDirectory.path == workingDirectory.path }) {
            activateSession(existing)
            return
        }

        // Otherwise create a new one
        createTerminalSession(workingDirectory: workingDirectory, label: branchName)
    }

    // MARK: - Terminal Paste

    func sendTextToActiveTerminal(_ text: String) {
        guard let activeID = activeTerminalID,
              !text.isEmpty else { return }
        sendTextToTerminal(text, sessionID: activeID)
    }

    func sendTextToTerminal(_ text: String, sessionID: UUID, activate: Bool = true) {
        guard !text.isEmpty,
              let callback = terminalSendCallbacks[sessionID],
              let data = text.data(using: .utf8) else { return }

        if activate,
           let session = terminalTabs.flatMap({ $0.allSessions() }).first(where: { $0.id == sessionID }) {
            activateTerminalSession(session)
        }

        callback(data)
    }

    func registerTerminalSendCallback(sessionID: UUID, callback: @escaping (Data) -> Void) {
        terminalSendCallbacks[sessionID] = callback
    }

    func unregisterTerminalSendCallback(sessionID: UUID) {
        terminalSendCallbacks.removeValue(forKey: sessionID)
    }

    func ensureTerminalBridgeHealth(context: String) {
        for session in terminalSessions {
            guard let coordinator = session._processBridge as? TerminalTabView.Coordinator else { continue }
            coordinator.ensureOwnerBinding(reason: context)
        }
    }

    // MARK: - Terminal Search

    var focusedTerminalView: SwiftTerm.TerminalView? {
        let session: TerminalSession? = {
            if let fid = focusedSessionID {
                return terminalTabs.flatMap({ $0.allSessions() }).first(where: { $0.id == fid })
            }
            return terminalTabs.first(where: { $0.id == activeTabID })?.allSessions().first
        }()
        return session?._cachedView as? SwiftTerm.TerminalView
    }

    func terminalFindNext(_ term: String) {
        _ = focusedTerminalView?.findNext(term)
    }

    func terminalFindPrevious(_ term: String) {
        _ = focusedTerminalView?.findPrevious(term)
    }

    func terminalClearSearch() {
        focusedTerminalView?.clearSearch()
    }

    func focusActiveTerminal() {
        guard let terminalView = focusedTerminalView else { return }
        DispatchQueue.main.async { [weak terminalView] in
            guard let terminalView else { return }
            terminalView.window?.makeFirstResponder(terminalView)
        }
    }
}
