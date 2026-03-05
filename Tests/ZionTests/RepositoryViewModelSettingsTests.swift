import XCTest
@testable import Zion

@MainActor
final class RepositoryViewModelSettingsTests: XCTestCase {

    // MARK: - languageName(for:)

    func testSwiftExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "swift"), "Swift")
    }

    func testTypeScriptExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "ts"), "TypeScript")
    }

    func testTSXExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "tsx"), "TypeScript")
    }

    func testPythonExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "py"), "Python")
    }

    func testGoExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "go"), "Go")
    }

    func testRustExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "rs"), "Rust")
    }

    func testMarkdownExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "md"), "Markdown")
    }

    func testUnknownExtensionUppercased() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "xyz"), "XYZ")
    }

    func testEmptyExtensionReturnsEmpty() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: ""), "")
    }

    // MARK: - Additional known extensions

    func testJavaScriptExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "js"), "JavaScript")
    }

    func testJSXExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "jsx"), "JavaScript")
    }

    func testRubyExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "rb"), "Ruby")
    }

    func testJavaExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "java"), "Java")
    }

    func testHTMLExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "html"), "HTML")
    }

    func testCSSExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "css"), "CSS")
    }

    func testJSONExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "json"), "JSON")
    }

    func testYAMLExtensions() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "yaml"), "YAML")
        XCTAssertEqual(RepositoryViewModel.languageName(for: "yml"), "YAML")
    }

    func testShellExtensions() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "sh"), "Shell")
        XCTAssertEqual(RepositoryViewModel.languageName(for: "bash"), "Shell")
        XCTAssertEqual(RepositoryViewModel.languageName(for: "zsh"), "Shell")
    }

    // MARK: - normalizeRecentRepositories

    func testNormalizeRecentRepositoriesDeduplicates() {
        let vm = RepositoryViewModel()
        let url1 = URL(fileURLWithPath: "/tmp/repo-a")
        let url2 = URL(fileURLWithPath: "/tmp/repo-b")
        let urls = [url1, url2, url1, url2, url1]

        let result = vm.normalizeRecentRepositories(urls)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].path, url1.path)
        XCTAssertEqual(result[1].path, url2.path)
    }

    func testNormalizeRecentRepositoriesPreservesOrder() {
        let vm = RepositoryViewModel()
        let url1 = URL(fileURLWithPath: "/tmp/repo-a")
        let url2 = URL(fileURLWithPath: "/tmp/repo-b")
        let url3 = URL(fileURLWithPath: "/tmp/repo-c")
        let urls = [url3, url1, url2]

        let result = vm.normalizeRecentRepositories(urls)

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].path, url3.path)
        XCTAssertEqual(result[1].path, url1.path)
        XCTAssertEqual(result[2].path, url2.path)
    }

    func testNormalizeRecentRepositoriesEmptyList() {
        let vm = RepositoryViewModel()
        let result = vm.normalizeRecentRepositories([])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - isCredentialFailure (Settings extension)

    func testIsCredentialFailureDetectsKeychain() {
        let vm = RepositoryViewModel()
        let error = GitClientError.commandFailed(command: "fetch", message: "git-credential-osxkeychain error")
        XCTAssertTrue(vm.isCredentialFailure(error))
    }

    func testIsCredentialFailureDetectsTerminalPromptsDisabled() {
        let vm = RepositoryViewModel()
        let error = GitClientError.commandFailed(command: "fetch", message: "fatal: terminal prompts disabled")
        XCTAssertTrue(vm.isCredentialFailure(error))
    }

    func testIsCredentialFailureDetectsDeviceNotConfigured() {
        let vm = RepositoryViewModel()
        let error = GitClientError.commandFailed(command: "fetch", message: "error: device not configured")
        XCTAssertTrue(vm.isCredentialFailure(error))
    }

    func testIsCredentialFailureDetectsAzureDevOps() {
        let vm = RepositoryViewModel()
        let error = GitClientError.commandFailed(command: "push", message: "fatal: unable to access 'https://dev.azure.com/org/project'")
        XCTAssertTrue(vm.isCredentialFailure(error))
    }

    func testIsNoUpstreamConfiguredNonGitErrorReturnsFalse() {
        let vm = RepositoryViewModel()
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "no upstream configured"])
        XCTAssertFalse(vm.isNoUpstreamConfigured(error))
    }

    // MARK: - Auto refresh divergence helper

    func testShouldRefreshAfterRemoteDivergenceUpdateWhenBehindChanges() {
        XCTAssertTrue(
            RepositoryViewModel.shouldRefreshAfterRemoteDivergenceUpdate(
                previousBehind: 0,
                previousAhead: 0,
                newBehind: 2,
                newAhead: 0
            )
        )
    }

    func testShouldRefreshAfterRemoteDivergenceUpdateWhenAheadChanges() {
        XCTAssertTrue(
            RepositoryViewModel.shouldRefreshAfterRemoteDivergenceUpdate(
                previousBehind: 1,
                previousAhead: 0,
                newBehind: 1,
                newAhead: 3
            )
        )
    }

    func testShouldRefreshAfterRemoteDivergenceUpdateWhenCountsUnchanged() {
        XCTAssertFalse(
            RepositoryViewModel.shouldRefreshAfterRemoteDivergenceUpdate(
                previousBehind: 2,
                previousAhead: 5,
                newBehind: 2,
                newAhead: 5
            )
        )
    }

    func testRefreshOriginGitActionUsesInteractiveDetails() {
        XCTAssertFalse(RepositoryViewModel.RefreshOrigin.gitAction.usesSilentCommitDetails)
    }
}
