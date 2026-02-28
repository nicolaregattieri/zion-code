import Foundation
import SwiftUI

@Observable @MainActor
final class TerminalSession: Identifiable {
    let id = UUID()
    let workingDirectory: URL
    let label: String
    let worktreeID: String?
    var isAlive = true
    var title: String

    // Cache for preserving terminal across SwiftUI view tree changes
    // (split/unsplit restructures the view hierarchy without user intent to close)
    @ObservationIgnored var _cachedView: AnyObject?       // SwiftTerm.TerminalView
    @ObservationIgnored var _processBridge: AnyObject?    // Coordinator (keeps it alive)
    @ObservationIgnored var _shellPid: Int32 = 0
    @ObservationIgnored var _shouldPreserve = true        // false after explicit kill

    init(workingDirectory: URL, label: String, worktreeID: String? = nil) {
        self.workingDirectory = workingDirectory
        self.label = label
        self.worktreeID = worktreeID
        self.title = label
    }

    /// Explicitly kill the terminal process and clear cached state.
    /// Call this only for intentional close (close tab, close pane, switch project).
    func killCachedProcess() {
        DiagnosticLogger.shared.log(.info, "killCachedProcess", context: "\(label)(\(id.uuidString.prefix(4))) pid=\(_shellPid) preserve=\(_shouldPreserve)", source: "TerminalSession")
        _shouldPreserve = false
        if _shellPid > 0 {
            kill(_shellPid, SIGTERM)
        }
        _shellPid = 0
        _cachedView = nil
        _processBridge = nil
    }
}

enum SplitDirection: String {
    case horizontal, vertical
}

@Observable @MainActor
final class TerminalPaneNode: Identifiable {
    let id = UUID()
    var content: PaneContent

    enum PaneContent {
        case terminal(TerminalSession)
        case split(direction: SplitDirection, first: TerminalPaneNode, second: TerminalPaneNode)
    }

    init(session: TerminalSession) {
        self.content = .terminal(session)
    }

    init(direction: SplitDirection, first: TerminalPaneNode, second: TerminalPaneNode) {
        self.content = .split(direction: direction, first: first, second: second)
    }

    /// Collect all terminal sessions in this subtree
    func allSessions() -> [TerminalSession] {
        switch content {
        case .terminal(let session):
            return [session]
        case .split(_, let first, let second):
            return first.allSessions() + second.allSessions()
        }
    }

    /// Find the node containing a specific session ID, returning the parent and which side
    func findNode(containing sessionID: UUID) -> TerminalPaneNode? {
        switch content {
        case .terminal(let session):
            return session.id == sessionID ? self : nil
        case .split(_, let first, let second):
            return first.findNode(containing: sessionID) ?? second.findNode(containing: sessionID)
        }
    }

    /// Flatten consecutive same-direction splits into a single array of children.
    /// Stops at direction boundaries (different-direction splits become leaf nodes).
    func flattenedChildren(forDirection target: SplitDirection) -> [TerminalPaneNode] {
        switch content {
        case .terminal:
            return [self]
        case .split(let direction, let first, let second):
            if direction == target {
                return first.flattenedChildren(forDirection: target)
                     + second.flattenedChildren(forDirection: target)
            } else {
                return [self]
            }
        }
    }

    /// Find parent of a node containing sessionID, returns (parent, isFirst)
    func findParent(of sessionID: UUID) -> (parent: TerminalPaneNode, isFirst: Bool)? {
        guard case .split(_, let first, let second) = content else { return nil }
        if case .terminal(let s) = first.content, s.id == sessionID {
            return (self, true)
        }
        if case .terminal(let s) = second.content, s.id == sessionID {
            return (self, false)
        }
        // Recurse into children
        if let found = first.findParent(of: sessionID) { return found }
        if let found = second.findParent(of: sessionID) { return found }
        return nil
    }
}
