import Foundation

struct CommitLoadPayload: Sendable {
    let commits: [Commit]
    let hasMore: Bool
    let selectedCommitID: String?
}

struct RepositoryLoadPayload: Sendable {
    let currentBranch: String
    let headShortHash: String
    let branchInfos: [BranchInfo]
    let branches: [String]
    let focusedBranch: String?
    let tags: [String]
    let stashes: [String]
    let selectedStash: String
    let worktrees: [WorktreeItem]
    let remotes: [RemoteInfo]
    let commits: [Commit]
    let hasMoreCommits: Bool
    let selectedCommitID: String?
    let hasConflicts: Bool
    let isMerging: Bool
    let isRebasing: Bool
    let isCherryPicking: Bool
    let isGitRepository: Bool
    let uncommittedChanges: [String]
    let uncommittedCount: Int
    let isBisecting: Bool
    let bisectCurrentHash: String
}

struct RepositoryLoadOptions: Sendable {
    let includeWorktreeStatus: Bool
    let includeTagsAndStashes: Bool

    static let full = RepositoryLoadOptions(
        includeWorktreeStatus: true,
        includeTagsAndStashes: true
    )

    static let critical = RepositoryLoadOptions(
        includeWorktreeStatus: false,
        includeTagsAndStashes: true
    )

    static let worktreeStatus = RepositoryLoadOptions(
        includeWorktreeStatus: true,
        includeTagsAndStashes: false
    )

    static let stashRefresh = RepositoryLoadOptions(
        includeWorktreeStatus: true,
        includeTagsAndStashes: true
    )
}
