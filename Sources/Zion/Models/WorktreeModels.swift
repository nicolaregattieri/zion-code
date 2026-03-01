import Foundation

struct WorktreeItem: Identifiable, Hashable, Sendable {
    let path: String
    let head: String
    let branch: String
    let isMainWorktree: Bool
    let isDetached: Bool
    let isLocked: Bool
    let lockReason: String
    let isPrunable: Bool
    let pruneReason: String
    let isCurrent: Bool
    let uncommittedCount: Int
    let hasConflicts: Bool

    init(
        path: String,
        head: String,
        branch: String,
        isMainWorktree: Bool,
        isDetached: Bool,
        isLocked: Bool,
        lockReason: String,
        isPrunable: Bool,
        pruneReason: String,
        isCurrent: Bool,
        uncommittedCount: Int = 0,
        hasConflicts: Bool = false
    ) {
        self.path = path
        self.head = head
        self.branch = branch
        self.isMainWorktree = isMainWorktree
        self.isDetached = isDetached
        self.isLocked = isLocked
        self.lockReason = lockReason
        self.isPrunable = isPrunable
        self.pruneReason = pruneReason
        self.isCurrent = isCurrent
        self.uncommittedCount = uncommittedCount
        self.hasConflicts = hasConflicts
    }

    var id: String { path }
}

enum WorktreePrefix: String, CaseIterable, Identifiable, Sendable {
    case feat
    case fix
    case chore
    case hotfix
    case exp

    var id: String { rawValue }

    var l10nKey: String {
        switch self {
        case .feat: return "worktree.prefix.feat"
        case .fix: return "worktree.prefix.fix"
        case .chore: return "worktree.prefix.chore"
        case .hotfix: return "worktree.prefix.hotfix"
        case .exp: return "worktree.prefix.exp"
        }
    }
}
