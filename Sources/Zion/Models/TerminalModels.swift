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
    @ObservationIgnored var _cachedTerminal: AnyObject?   // SwiftTerm.Terminal (direct ref for remote access)
    @ObservationIgnored var _processBridge: AnyObject?    // Coordinator (keeps it alive)
    @ObservationIgnored var _activeCoordinatorGeneration: UUID?
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
        let pid = _shellPid
        if pid > 0 {
            kill(pid, SIGTERM)
            // Escalate to SIGKILL for frozen processes that ignore SIGTERM
            Task {
                try? await Task.sleep(nanoseconds: Constants.Timing.processKillEscalation)
                if kill(pid, 0) == 0 {
                    kill(pid, SIGKILL)
                }
            }
        }
        _shellPid = 0
        // Hide the NSView immediately so it vanishes before SwiftUI's dismantle cycle
        if let view = _cachedView as? NSView {
            view.isHidden = true
            view.removeFromSuperview()
        }
        _cachedView = nil
        _cachedTerminal = nil
        _processBridge = nil
        _activeCoordinatorGeneration = nil
    }
}

enum SplitDirection: String {
    case horizontal, vertical
}

@Observable @MainActor
final class TerminalPaneNode: Identifiable {
    let id = UUID()
    var content: PaneContent
    /// Fraction of space allocated to the `first` child in a `.split` node (0...1)
    var ratio: CGFloat = 0.5

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

    /// Walk a same-direction split chain and set ratios so all leaves get equal space.
    /// Pattern: for N leaves, ratios from root to deepest are 1/N, 1/(N-1), ..., 1/2.
    func redistributeEqualRatios(forDirection target: SplitDirection) {
        let leafCount = flattenedChildren(forDirection: target).count
        guard leafCount > 1 else { return }
        applyChainRatios(forDirection: target, remaining: leafCount)
    }

    private func applyChainRatios(forDirection target: SplitDirection, remaining: Int) {
        guard case .split(let direction, let first, let second) = content,
              direction == target, remaining > 1 else { return }
        ratio = 1.0 / CGFloat(remaining)
        second.applyChainRatios(forDirection: target, remaining: remaining - 1)
        first.applyChainRatios(forDirection: target, remaining: 1) // first is always a leaf or cross-direction
    }

    /// Check if this subtree contains a node with the given node ID
    func containsNode(id nodeID: UUID) -> Bool {
        if self.id == nodeID { return true }
        guard case .split(_, let first, let second) = content else { return false }
        return first.containsNode(id: nodeID) || second.containsNode(id: nodeID)
    }

    /// Find the topmost ancestor in the same-direction chain that contains a given node ID.
    /// Searches from `root` downward. Returns the highest split node whose direction matches
    /// `target` and whose subtree contains `nodeID`.
    static func findSameDirectionChainRoot(
        in root: TerminalPaneNode,
        containing nodeID: UUID,
        direction target: SplitDirection
    ) -> TerminalPaneNode? {
        guard case .split(let dir, let first, let second) = root.content else { return nil }
        guard root.containsNode(id: nodeID) else { return nil }
        if dir == target {
            return root
        }
        // Direction mismatch -- look deeper
        return findSameDirectionChainRoot(in: first, containing: nodeID, direction: target)
            ?? findSameDirectionChainRoot(in: second, containing: nodeID, direction: target)
    }
}
