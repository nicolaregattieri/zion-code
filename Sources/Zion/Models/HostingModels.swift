import Foundation

// MARK: - Provider-Agnostic Remote & PR Types

/// Represents a parsed remote pointing to a hosted repository.
struct HostedRemote: Sendable {
    let kind: GitHostingKind
    let owner: String
    let repo: String
    /// For self-hosted instances (GitLab CE/EE). Nil for cloud-hosted services.
    let host: String?

    init(kind: GitHostingKind, owner: String, repo: String, host: String? = nil) {
        self.kind = kind
        self.owner = owner
        self.repo = repo
        self.host = host
    }

    /// Base API URL for this remote.
    var apiBaseURL: String {
        switch kind {
        case .github:
            return "https://api.github.com"
        case .gitlab:
            let h = host ?? "gitlab.com"
            return "https://\(h)/api/v4"
        case .bitbucket:
            return "https://api.bitbucket.org/2.0"
        }
    }
}

/// Provider-agnostic pull/merge request info.
struct HostedPRInfo: Identifiable, Sendable {
    let id: Int
    let number: Int
    let title: String
    let state: PRState
    let headBranch: String
    let baseBranch: String
    let url: String
    let isDraft: Bool
    let author: String
    let headSHA: String

    enum PRState: String, Sendable {
        case open, closed, merged

        var label: String {
            switch self {
            case .open: return "Open"
            case .closed: return "Closed"
            case .merged: return "Merged"
            }
        }
    }
}

// MARK: - Backward Compatibility

/// Typealias for migration — existing code referencing GitHubPRInfo still compiles.
typealias GitHubPRInfo = HostedPRInfo
/// Typealias for migration — existing code referencing GitHubRemote still compiles.
typealias GitHubRemote = HostedRemote

// MARK: - PR Comments & Reviews (Phase 2)

/// An inline comment on a PR diff.
struct PRComment: Identifiable, Sendable {
    let id: Int
    let author: String
    let body: String
    let path: String
    let line: Int?
    let createdAt: Date
    let updatedAt: Date
    let inReplyToID: Int?
}

/// Summary of a PR review.
struct PRReviewSummary: Identifiable, Sendable {
    let id: Int
    let author: String
    let state: PRReviewEvent
    let body: String
    let submittedAt: Date?
}

/// Review action when submitting a review.
enum PRReviewEvent: String, Sendable, CaseIterable, Identifiable {
    case comment = "COMMENT"
    case approve = "APPROVE"
    case requestChanges = "REQUEST_CHANGES"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .comment: return L10n("pr.review.state.comment")
        case .approve: return L10n("pr.review.state.approve")
        case .requestChanges: return L10n("pr.review.state.requestChanges")
        }
    }

    var icon: String {
        switch self {
        case .comment: return "text.bubble"
        case .approve: return "checkmark.circle.fill"
        case .requestChanges: return "xmark.circle.fill"
        }
    }
}

/// A draft comment attached to a pending review submission.
struct PRReviewDraftComment: Sendable {
    let path: String
    let line: Int
    let body: String
}
