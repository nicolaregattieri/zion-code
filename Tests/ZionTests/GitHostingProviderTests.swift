import XCTest
@testable import Zion

final class GitHostingProviderTests: XCTestCase {

    // MARK: - GitHub Remote Parsing

    func testGitHubParseHTTPS() {
        let remote = GitHubClient.parseRemote("https://github.com/octocat/Hello-World.git")
        XCTAssertNotNil(remote)
        XCTAssertEqual(remote?.kind, .github)
        XCTAssertEqual(remote?.owner, "octocat")
        XCTAssertEqual(remote?.repo, "Hello-World")
        XCTAssertNil(remote?.host)
    }

    func testGitHubParseHTTPSWithoutGit() {
        let remote = GitHubClient.parseRemote("https://github.com/octocat/Hello-World")
        XCTAssertNotNil(remote)
        XCTAssertEqual(remote?.owner, "octocat")
        XCTAssertEqual(remote?.repo, "Hello-World")
    }

    func testGitHubParseSSH() {
        let remote = GitHubClient.parseRemote("git@github.com:octocat/Hello-World.git")
        XCTAssertNotNil(remote)
        XCTAssertEqual(remote?.kind, .github)
        XCTAssertEqual(remote?.owner, "octocat")
        XCTAssertEqual(remote?.repo, "Hello-World")
    }

    func testGitHubParseSSHWithoutGit() {
        let remote = GitHubClient.parseRemote("git@github.com:octocat/Hello-World")
        XCTAssertNotNil(remote)
        XCTAssertEqual(remote?.owner, "octocat")
        XCTAssertEqual(remote?.repo, "Hello-World")
    }

    func testGitHubRejectsGitLab() {
        let remote = GitHubClient.parseRemote("https://gitlab.com/user/repo.git")
        XCTAssertNil(remote)
    }

    func testGitHubRejectsBitbucket() {
        let remote = GitHubClient.parseRemote("https://bitbucket.org/user/repo.git")
        XCTAssertNil(remote)
    }

    // MARK: - GitLab Remote Parsing

    func testGitLabParseHTTPS() {
        let remote = GitLabClient.parseRemote("https://gitlab.com/user/project.git")
        XCTAssertNotNil(remote)
        XCTAssertEqual(remote?.kind, .gitlab)
        XCTAssertEqual(remote?.owner, "user")
        XCTAssertEqual(remote?.repo, "project")
        XCTAssertNil(remote?.host)
    }

    func testGitLabParseSSH() {
        let remote = GitLabClient.parseRemote("git@gitlab.com:user/project.git")
        XCTAssertNotNil(remote)
        XCTAssertEqual(remote?.kind, .gitlab)
        XCTAssertEqual(remote?.owner, "user")
        XCTAssertEqual(remote?.repo, "project")
        XCTAssertNil(remote?.host)
    }

    func testGitLabParseSubgroup() {
        let remote = GitLabClient.parseRemote("git@gitlab.com:group/subgroup/project.git")
        XCTAssertNotNil(remote)
        XCTAssertEqual(remote?.owner, "group/subgroup")
        XCTAssertEqual(remote?.repo, "project")
    }

    func testGitLabParseSelfHostedSSH() {
        let remote = GitLabClient.parseRemote("git@gitlab.mycompany.com:team/project.git")
        XCTAssertNotNil(remote)
        XCTAssertEqual(remote?.kind, .gitlab)
        XCTAssertEqual(remote?.owner, "team")
        XCTAssertEqual(remote?.repo, "project")
        XCTAssertEqual(remote?.host, "gitlab.mycompany.com")
    }

    func testGitLabRejectsGitHub() {
        let remote = GitLabClient.parseRemote("https://github.com/user/repo.git")
        XCTAssertNil(remote)
    }

    func testGitLabRejectsBitbucket() {
        let remote = GitLabClient.parseRemote("https://bitbucket.org/user/repo.git")
        XCTAssertNil(remote)
    }

    // MARK: - Bitbucket Remote Parsing

    func testBitbucketParseHTTPS() {
        let remote = BitbucketClient.parseRemote("https://bitbucket.org/user/repo.git")
        XCTAssertNotNil(remote)
        XCTAssertEqual(remote?.kind, .bitbucket)
        XCTAssertEqual(remote?.owner, "user")
        XCTAssertEqual(remote?.repo, "repo")
    }

    func testBitbucketParseSSH() {
        let remote = BitbucketClient.parseRemote("git@bitbucket.org:user/repo.git")
        XCTAssertNotNil(remote)
        XCTAssertEqual(remote?.kind, .bitbucket)
        XCTAssertEqual(remote?.owner, "user")
        XCTAssertEqual(remote?.repo, "repo")
    }

    func testBitbucketRejectsGitHub() {
        let remote = BitbucketClient.parseRemote("https://github.com/user/repo.git")
        XCTAssertNil(remote)
    }

    func testBitbucketRejectsGitLab() {
        let remote = BitbucketClient.parseRemote("https://gitlab.com/user/repo.git")
        XCTAssertNil(remote)
    }

    // MARK: - HostedRemote API Base URL

    func testGitHubAPIBaseURL() {
        let remote = HostedRemote(kind: .github, owner: "user", repo: "repo")
        XCTAssertEqual(remote.apiBaseURL, "https://api.github.com")
    }

    func testGitLabCloudAPIBaseURL() {
        let remote = HostedRemote(kind: .gitlab, owner: "user", repo: "repo")
        XCTAssertEqual(remote.apiBaseURL, "https://gitlab.com/api/v4")
    }

    func testGitLabSelfHostedAPIBaseURL() {
        let remote = HostedRemote(kind: .gitlab, owner: "user", repo: "repo", host: "gitlab.mycompany.com")
        XCTAssertEqual(remote.apiBaseURL, "https://gitlab.mycompany.com/api/v4")
    }

    func testBitbucketAPIBaseURL() {
        let remote = HostedRemote(kind: .bitbucket, owner: "user", repo: "repo")
        XCTAssertEqual(remote.apiBaseURL, "https://api.bitbucket.org/2.0")
    }

    // MARK: - GitHostingKind

    func testGitHostingKindLabels() {
        XCTAssertFalse(GitHostingKind.github.label.isEmpty)
        XCTAssertFalse(GitHostingKind.gitlab.label.isEmpty)
        XCTAssertFalse(GitHostingKind.bitbucket.label.isEmpty)
    }

    func testGitHostingKindCaseIterable() {
        XCTAssertEqual(GitHostingKind.allCases.count, 3)
    }

    // MARK: - Typealias Backward Compatibility

    func testGitHubPRInfoTypealias() {
        // GitHubPRInfo should be usable as a type (it's a typealias to HostedPRInfo)
        let pr: GitHubPRInfo = HostedPRInfo(
            id: 1, number: 42, title: "Test PR", state: .open,
            headBranch: "feature", baseBranch: "main",
            url: "https://github.com/user/repo/pull/42",
            isDraft: false, author: "testuser", headSHA: "abc123"
        )
        XCTAssertEqual(pr.number, 42)
        XCTAssertEqual(pr.headSHA, "abc123")
    }

    func testGitHubRemoteTypealias() {
        // GitHubRemote should be usable (typealias to HostedRemote)
        let remote: GitHubRemote = HostedRemote(kind: .github, owner: "user", repo: "repo")
        XCTAssertEqual(remote.owner, "user")
    }
}
