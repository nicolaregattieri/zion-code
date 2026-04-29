import AppKit
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
                if case .split(let direction, let first, let second) = parent.content {
                    let survivor = isFirst ? second : first
                    parent.content = survivor.content
                    // Copy ratio from survivor so nested splits preserve their shape
                    parent.ratio = survivor.ratio

                    // Redistribute the surviving same-direction chain so panes are equal
                    if let chainRoot = TerminalPaneNode.findSameDirectionChainRoot(
                        in: tab, containing: parent.id, direction: direction
                    ) {
                        chainRoot.redistributeEqualRatios(forDirection: direction)
                    } else {
                        // parent itself may be the chain root
                        parent.redistributeEqualRatios(forDirection: direction)
                    }
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
                    node.ratio = 0.5
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
                    node.ratio = 0.5
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

    func ensureDefaultTerminalSession(repositoryURL: URL?, branchName: String) {
        guard terminalTabs.isEmpty else { return }
        createDefaultTerminalSession(repositoryURL: repositoryURL, branchName: branchName)
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

    // MARK: - Terminal Image Paste

    /// Stages an image on `NSPasteboard.general` and sends Ctrl+V to the active
    /// terminal so TUIs (Claude Code, Codex) render the native `[Image]`
    /// placeholder instead of a raw shell-quoted path.
    func pasteImageFromPathToActiveTerminal(_ path: String) {
        guard let activeID = activeTerminalID else { return }
        pasteImageFromPathToTerminal(path, sessionID: activeID)
    }

    /// Per-session variant used by the terminal pane's SwiftUI drop overlay.
    func pasteImageFromPathToTerminal(_ path: String, sessionID: UUID) {
        guard let callback = terminalSendCallbacks[sessionID] else { return }
        let fileURL = URL(fileURLWithPath: path)
        guard ZionTerminalView.stageImageOnPasteboard(urls: [fileURL]) else { return }

        if let session = terminalTabs
            .flatMap({ $0.allSessions() })
            .first(where: { $0.id == sessionID }) {
            activateTerminalSession(session)
        }

        callback(Data([0x16]))
    }

    /// Routes a list of dropped file URLs onto the given session: images take
    /// the image-paste path (`[Image]` placeholder), non-images fall back to
    /// shell-escaped text paste. Returns true if at least one URL was handled.
    @discardableResult
    func handleFileURLsDroppedOnTerminal(_ urls: [URL], sessionID: UUID) -> Bool {
        let fileURLs = urls.filter { $0.isFileURL }
        guard !fileURLs.isEmpty else { return false }

        let imageURLs = fileURLs.filter { ZionTerminalView.isImageFile($0) }
        let nonImageURLs = fileURLs.filter { !ZionTerminalView.isImageFile($0) }

        var handled = false

        if let first = imageURLs.first,
           let callback = terminalSendCallbacks[sessionID],
           ZionTerminalView.stageImageOnPasteboard(urls: [first]) {
            callback(Data([0x16]))
            handled = true
        }

        if !nonImageURLs.isEmpty {
            let escaped = TerminalShellEscaping.joinQuotedFileURLs(nonImageURLs)
            if !escaped.isEmpty {
                sendTextToTerminal(escaped, sessionID: sessionID)
                handled = true
            }
        }

        return handled
    }

    // MARK: - Terminal file-reference open

    /// Resolves a path-like token clicked in the terminal and opens it in the
    /// Zion editor when it points to a real file. Supports absolute paths,
    /// tilde-expanded paths, `file://` URLs, and paths relative to the given
    /// session working directory (falls back to the current repository URL).
    /// Strips an optional `:line:col` suffix and jumps to that line after
    /// opening.
    func openPathFromTerminal(_ rawToken: String, sessionWorkingDirectory: URL?) {
        let trimmed = rawToken
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'<>()[]{}"))
        guard !trimmed.isEmpty else { return }

        let resolution = Self.resolveTerminalPath(
            token: trimmed,
            sessionWorkingDirectory: sessionWorkingDirectory,
            repositoryURL: repositoryURL,
            fileManager: FileManager.default
        )
        guard let resolution else { return }

        openExternalFiles([resolution.url])
        if let line = resolution.line {
            editorJumpLineTarget = line
            editorJumpToken += 1
        }
    }

    struct TerminalPathResolution: Equatable {
        let url: URL
        let line: Int?
        let column: Int?
    }

    static func resolveTerminalPath(
        token: String,
        sessionWorkingDirectory: URL?,
        repositoryURL: URL?,
        fileManager: FileManager
    ) -> TerminalPathResolution? {
        let (base, line, column) = splitLineColumnSuffix(token)

        let candidates = pathCandidates(
            base: base,
            sessionWorkingDirectory: sessionWorkingDirectory,
            repositoryURL: repositoryURL
        )

        for path in candidates {
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue {
                return TerminalPathResolution(
                    url: URL(fileURLWithPath: path),
                    line: line,
                    column: column
                )
            }
        }
        return nil
    }

    private static func pathCandidates(
        base: String,
        sessionWorkingDirectory: URL?,
        repositoryURL: URL?
    ) -> [String] {
        var results: [String] = []

        if base.hasPrefix("file://"), let url = URL(string: base), url.isFileURL {
            results.append(url.path)
        }
        if base.hasPrefix("/") {
            results.append(base)
        } else if base.hasPrefix("~") {
            results.append((base as NSString).expandingTildeInPath)
        } else {
            if let cwd = sessionWorkingDirectory {
                results.append(cwd.appendingPathComponent(base).path)
            }
            if let repo = repositoryURL, repo != sessionWorkingDirectory {
                results.append(repo.appendingPathComponent(base).path)
            }
        }
        return results
    }

    private static func splitLineColumnSuffix(_ token: String) -> (base: String, line: Int?, column: Int?) {
        // Matches tails like ":123" or ":123:45" on the end of the token.
        let nsString = token as NSString
        let range = NSRange(location: 0, length: nsString.length)
        let pattern = #":(\d+)(?::(\d+))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: token, range: range) else {
            return (token, nil, nil)
        }
        let base = nsString.substring(to: match.range.location)
        let line = Int(nsString.substring(with: match.range(at: 1)))
        let columnRange = match.range(at: 2)
        let column: Int? = columnRange.location == NSNotFound
            ? nil
            : Int(nsString.substring(with: columnRange))
        return (base, line, column)
    }

    func ensureTerminalBridgeHealth(context: String) {
        for session in terminalSessions {
            guard let coordinator = session._processBridge as? TerminalTabView.Coordinator else { continue }
            coordinator.ensureOwnerBinding(reason: context)
        }
    }

    // MARK: - Terminal Search

    var focusedTerminalView: SwiftTerm.TerminalView? {
        // Prefer the actual AppKit first responder so split-pane find scopes
        // to the pane the user is typing in, not a stale focusedSessionID
        // that only updates on tap.
        if let window = NSApp.keyWindow,
           var node = window.firstResponder as? NSView {
            while true {
                if let term = node as? SwiftTerm.TerminalView { return term }
                guard let parent = node.superview else { break }
                node = parent
            }
        }
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
