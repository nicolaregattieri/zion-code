import Foundation

/// Identifies the kind of git hosting service.
enum GitHostingKind: String, Sendable, CaseIterable, Identifiable {
    case github
    case gitlab
    case bitbucket

    var id: String { rawValue }

    var label: String {
        switch self {
        case .github: return L10n("hosting.provider.github")
        case .gitlab: return L10n("hosting.provider.gitlab")
        case .bitbucket: return L10n("hosting.provider.bitbucket")
        }
    }

    var icon: String {
        switch self {
        case .github: return "arrow.triangle.branch"
        case .gitlab: return "arrow.triangle.branch"
        case .bitbucket: return "arrow.triangle.branch"
        }
    }
}

/// Protocol for git hosting provider integrations (GitHub, GitLab, Bitbucket).
protocol GitHostingProvider: Actor {
    /// The kind of hosting provider this actor represents.
    var kind: GitHostingKind { get }

    /// Attempt to parse a remote URL into a hosted remote. Returns nil if the URL doesn't match this provider.
    static func parseRemote(_ urlString: String) -> HostedRemote?

    /// Check if authentication is configured for this provider.
    func checkAuthStatus() -> (installed: Bool, authenticated: Bool)

    /// Fetch open pull/merge requests for a hosted remote.
    func fetchPullRequests(remote: HostedRemote) async -> [HostedPRInfo]

    /// Fetch PRs/MRs requesting review from the authenticated user.
    func fetchPRsRequestingMyReview(remote: HostedRemote) async -> [HostedPRInfo]

    /// Fetch the unified diff for a specific PR/MR.
    func fetchPRDiff(remote: HostedRemote, prNumber: Int) async -> String?

    /// Fetch files changed in a PR/MR.
    func fetchPRFiles(remote: HostedRemote, prNumber: Int) async -> [(filename: String, status: String, additions: Int, deletions: Int, patch: String)]

    /// Create a new pull/merge request.
    func createPullRequest(remote: HostedRemote, title: String, body: String, head: String, base: String, draft: Bool) async throws -> HostedPRInfo

    // MARK: - Review & Comments (Phase 2)

    /// Fetch inline comments for a PR/MR.
    func fetchPRComments(remote: HostedRemote, prNumber: Int) async -> [PRComment]

    /// Post an inline comment on a PR/MR diff.
    func postPRComment(remote: HostedRemote, prNumber: Int, body: String, commitID: String, path: String, line: Int) async throws -> PRComment

    /// Fetch review summaries for a PR/MR.
    func fetchPRReviews(remote: HostedRemote, prNumber: Int) async -> [PRReviewSummary]

    /// Submit a review (approve, request changes, or comment).
    func submitPRReview(remote: HostedRemote, prNumber: Int, body: String, event: PRReviewEvent, comments: [PRReviewDraftComment]) async throws
}

/// Default implementations for optional Phase 2 methods — providers can override as they add support.
extension GitHostingProvider {
    func fetchPRComments(remote: HostedRemote, prNumber: Int) async -> [PRComment] { [] }
    func postPRComment(remote: HostedRemote, prNumber: Int, body: String, commitID: String, path: String, line: Int) async throws -> PRComment {
        throw HostingError.notSupported
    }
    func fetchPRReviews(remote: HostedRemote, prNumber: Int) async -> [PRReviewSummary] { [] }
    func submitPRReview(remote: HostedRemote, prNumber: Int, body: String, event: PRReviewEvent, comments: [PRReviewDraftComment]) async throws {
        throw HostingError.notSupported
    }
}

enum HostingError: LocalizedError {
    case noToken
    case invalidURL
    case apiError(String)
    case parseError
    case notSupported

    var errorDescription: String? {
        switch self {
        case .noToken: return L10n("github.error.noToken")
        case .invalidURL: return L10n("github.error.invalidURL")
        case .apiError(let msg): return L10n("github.error.api", msg)
        case .parseError: return L10n("github.error.parseError")
        case .notSupported: return L10n("hosting.notSupported")
        }
    }
}
