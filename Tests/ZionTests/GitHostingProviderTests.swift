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

    func testGitHubParseSSHAlias() {
        let remote = GitHubClient.parseRemote("git@github.com-personal:octocat/Hello-World.git")
        XCTAssertNotNil(remote)
        XCTAssertEqual(remote?.kind, .github)
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
        XCTAssertFalse(GitHostingKind.azureDevOps.label.isEmpty)
    }

    func testGitHostingKindCaseIterable() {
        XCTAssertEqual(GitHostingKind.allCases.count, 4)
    }

    // MARK: - Azure DevOps Remote Parsing

    func testADOParseHTTPSDevAzureCom() {
        let remote = AzureDevOpsClient.parseRemote("https://dev.azure.com/myorg/myproject/_git/myrepo")
        XCTAssertNotNil(remote)
        XCTAssertEqual(remote?.kind, .azureDevOps)
        XCTAssertEqual(remote?.owner, "myorg")
        XCTAssertEqual(remote?.repo, "myrepo")
        XCTAssertEqual(remote?.project, "myproject")
        XCTAssertEqual(remote?.host, "dev.azure.com")
    }

    func testADOParseHTTPSVisualStudioCom() {
        let remote = AzureDevOpsClient.parseRemote("https://myorg.visualstudio.com/myproject/_git/myrepo")
        XCTAssertNotNil(remote)
        XCTAssertEqual(remote?.kind, .azureDevOps)
        XCTAssertEqual(remote?.owner, "myorg")
        XCTAssertEqual(remote?.repo, "myrepo")
        XCTAssertEqual(remote?.project, "myproject")
    }

    func testADOParseSSHDevAzureCom() {
        let remote = AzureDevOpsClient.parseRemote("git@ssh.dev.azure.com:v3/myorg/myproject/myrepo")
        XCTAssertNotNil(remote)
        XCTAssertEqual(remote?.kind, .azureDevOps)
        XCTAssertEqual(remote?.owner, "myorg")
        XCTAssertEqual(remote?.repo, "myrepo")
        XCTAssertEqual(remote?.project, "myproject")
    }

    func testADOParseSSHVisualStudioCom() {
        let remote = AzureDevOpsClient.parseRemote("git@vs-ssh.visualstudio.com:v3/myorg/myproject/myrepo")
        XCTAssertNotNil(remote)
        XCTAssertEqual(remote?.kind, .azureDevOps)
        XCTAssertEqual(remote?.owner, "myorg")
        XCTAssertEqual(remote?.repo, "myrepo")
        XCTAssertEqual(remote?.project, "myproject")
    }

    func testADORejectsGitHub() {
        let remote = AzureDevOpsClient.parseRemote("https://github.com/user/repo.git")
        XCTAssertNil(remote)
    }

    func testADORejectsGitLab() {
        let remote = AzureDevOpsClient.parseRemote("https://gitlab.com/user/repo.git")
        XCTAssertNil(remote)
    }

    func testADORejectsBitbucket() {
        let remote = AzureDevOpsClient.parseRemote("https://bitbucket.org/user/repo.git")
        XCTAssertNil(remote)
    }

    func testADOAPIBaseURL() {
        let remote = HostedRemote(kind: .azureDevOps, owner: "myorg", repo: "myrepo", project: "myproject")
        XCTAssertEqual(remote.apiBaseURL, "https://dev.azure.com/myorg")
    }

    func testADOAPIBaseURLWithCustomHost() {
        let remote = HostedRemote(kind: .azureDevOps, owner: "myorg", repo: "myrepo", host: "ado.mycompany.com", project: "myproject")
        XCTAssertEqual(remote.apiBaseURL, "https://ado.mycompany.com/myorg")
    }

    // MARK: - HostedRemote project field

    func testHostedRemoteProjectDefaultsToNil() {
        let remote = HostedRemote(kind: .github, owner: "user", repo: "repo")
        XCTAssertNil(remote.project)
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

    // MARK: - Lazy Keychain Token Loading

    func testGitLabHasTokenLoadsFromKeychainOnDemand() async {
        let key = HostingCredentialStore.CredentialKey.gitlabPAT
        let original = HostingCredentialStore.loadSecret(for: key)
        defer {
            if let original { HostingCredentialStore.saveSecret(original, for: key) }
            else { HostingCredentialStore.deleteSecret(for: key) }
        }

        HostingCredentialStore.saveSecret("gitlab-on-demand-token", for: key)
        let client = GitLabClient()

        let hasToken = await client.hasToken()
        XCTAssertTrue(hasToken)
    }

    func testAzureHasTokenLoadsFromKeychainOnDemand() async {
        let key = HostingCredentialStore.CredentialKey.azureDevOpsPAT
        let original = HostingCredentialStore.loadSecret(for: key)
        defer {
            if let original { HostingCredentialStore.saveSecret(original, for: key) }
            else { HostingCredentialStore.deleteSecret(for: key) }
        }

        HostingCredentialStore.saveSecret("azure-on-demand-token", for: key)
        let client = AzureDevOpsClient()

        let hasToken = await client.hasToken()
        XCTAssertTrue(hasToken)
    }

    func testBitbucketHasTokenLoadsFromKeychainOnDemand() async {
        let key = HostingCredentialStore.CredentialKey.bitbucketAppPassword
        let defaults = UserDefaults.standard
        let originalSecret = HostingCredentialStore.loadSecret(for: key)
        let originalUsername = defaults.string(forKey: "zion.bitbucket.username")
        defer {
            if let originalSecret { HostingCredentialStore.saveSecret(originalSecret, for: key) }
            else { HostingCredentialStore.deleteSecret(for: key) }
            if let originalUsername {
                defaults.set(originalUsername, forKey: "zion.bitbucket.username")
            } else {
                defaults.removeObject(forKey: "zion.bitbucket.username")
            }
        }

        defaults.set("bitbucket-user", forKey: "zion.bitbucket.username")
        HostingCredentialStore.saveSecret("bitbucket-on-demand-pass", for: key)
        let client = BitbucketClient()

        let hasToken = await client.hasToken()
        XCTAssertTrue(hasToken)
    }
}
