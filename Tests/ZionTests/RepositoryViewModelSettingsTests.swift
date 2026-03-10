import XCTest
@testable import Zion

final class RepositoryViewModelSettingsTests: XCTestCase {
    private let lineWrapKey = "editor.lineWrap"
    private var savedLineWrapValue: Any?

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        savedLineWrapValue = defaults.object(forKey: lineWrapKey)
        defaults.removeObject(forKey: lineWrapKey)
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        if let savedLineWrapValue {
            defaults.set(savedLineWrapValue, forKey: lineWrapKey)
        } else {
            defaults.removeObject(forKey: lineWrapKey)
        }
        savedLineWrapValue = nil
        super.tearDown()
    }

    // MARK: - languageName(for:)

    @MainActor
    func testSwiftExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "swift"), "Swift")
    }

    @MainActor
    func testTypeScriptExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "ts"), "TypeScript")
    }

    @MainActor
    func testTSXExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "tsx"), "TypeScript")
    }

    @MainActor
    func testPythonExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "py"), "Python")
    }

    @MainActor
    func testGoExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "go"), "Go")
    }

    @MainActor
    func testRustExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "rs"), "Rust")
    }

    @MainActor
    func testMarkdownExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "md"), "Markdown")
    }

    @MainActor
    func testUnknownExtensionUppercased() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "xyz"), "XYZ")
    }

    @MainActor
    func testEmptyExtensionReturnsEmpty() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: ""), "")
    }

    // MARK: - Additional known extensions

    @MainActor
    func testJavaScriptExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "js"), "JavaScript")
    }

    @MainActor
    func testJSXExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "jsx"), "JavaScript")
    }

    @MainActor
    func testRubyExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "rb"), "Ruby")
    }

    @MainActor
    func testJavaExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "java"), "Java")
    }

    @MainActor
    func testHTMLExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "html"), "HTML")
    }

    @MainActor
    func testCSSExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "css"), "CSS")
    }

    @MainActor
    func testJSONExtension() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "json"), "JSON")
    }

    @MainActor
    func testYAMLExtensions() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "yaml"), "YAML")
        XCTAssertEqual(RepositoryViewModel.languageName(for: "yml"), "YAML")
    }

    @MainActor
    func testShellExtensions() {
        XCTAssertEqual(RepositoryViewModel.languageName(for: "sh"), "Shell")
        XCTAssertEqual(RepositoryViewModel.languageName(for: "bash"), "Shell")
        XCTAssertEqual(RepositoryViewModel.languageName(for: "zsh"), "Shell")
    }

    // MARK: - normalizeRecentRepositories

    @MainActor
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

    @MainActor
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

    @MainActor
    func testNormalizeRecentRepositoriesEmptyList() {
        let vm = RepositoryViewModel()
        let result = vm.normalizeRecentRepositories([])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - recentChangedCount(for:)

    @MainActor
    func testRecentChangedCountUsesLiveCountForCurrentRepository() {
        let vm = RepositoryViewModel()
        let current = URL(fileURLWithPath: "/tmp/repo-current")
        vm.repositoryURL = current
        vm.uncommittedCount = 7
        vm.backgroundRepoChangedFiles[current] = 2

        let count = vm.recentChangedCount(for: current)

        XCTAssertEqual(count, 7)
    }

    @MainActor
    func testRecentChangedCountUsesBackgroundCountForInactiveRepository() {
        let vm = RepositoryViewModel()
        let current = URL(fileURLWithPath: "/tmp/repo-current")
        let inactive = URL(fileURLWithPath: "/tmp/repo-inactive")
        vm.repositoryURL = current
        vm.uncommittedCount = 4
        vm.backgroundRepoChangedFiles[inactive] = 3

        let count = vm.recentChangedCount(for: inactive)

        XCTAssertEqual(count, 3)
    }

    @MainActor
    func testRecentChangedCountReturnsNilWhenInactiveRepositoryIsUnknown() {
        let vm = RepositoryViewModel()
        vm.repositoryURL = URL(fileURLWithPath: "/tmp/repo-current")

        let count = vm.recentChangedCount(for: URL(fileURLWithPath: "/tmp/repo-unknown"))

        XCTAssertNil(count)
    }

    // MARK: - isCredentialFailure (Settings extension)

    @MainActor
    func testIsCredentialFailureDetectsKeychain() {
        let vm = RepositoryViewModel()
        let error = GitClientError.commandFailed(command: "fetch", message: "git-credential-osxkeychain error")
        XCTAssertTrue(vm.isCredentialFailure(error))
    }

    @MainActor
    func testIsCredentialFailureDetectsTerminalPromptsDisabled() {
        let vm = RepositoryViewModel()
        let error = GitClientError.commandFailed(command: "fetch", message: "fatal: terminal prompts disabled")
        XCTAssertTrue(vm.isCredentialFailure(error))
    }

    @MainActor
    func testIsCredentialFailureDetectsDeviceNotConfigured() {
        let vm = RepositoryViewModel()
        let error = GitClientError.commandFailed(command: "fetch", message: "error: device not configured")
        XCTAssertTrue(vm.isCredentialFailure(error))
    }

    @MainActor
    func testIsCredentialFailureDetectsAzureDevOps() {
        let vm = RepositoryViewModel()
        let error = GitClientError.commandFailed(command: "push", message: "fatal: unable to access 'https://dev.azure.com/org/project'")
        XCTAssertTrue(vm.isCredentialFailure(error))
    }

    @MainActor
    func testIsNoUpstreamConfiguredNonGitErrorReturnsFalse() {
        let vm = RepositoryViewModel()
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "no upstream configured"])
        XCTAssertFalse(vm.isNoUpstreamConfigured(error))
    }

    // MARK: - Auto refresh divergence helper

    @MainActor
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

    @MainActor
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

    @MainActor
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

    @MainActor
    func testRefreshOriginGitActionUsesInteractiveDetails() {
        XCTAssertFalse(RepositoryViewModel.RefreshOrigin.gitAction.usesSilentCommitDetails)
    }

    // MARK: - Inactive background monitor policy

    @MainActor
    func testNextInactiveMonitorIntervalUsesIdleWhenNoBurst() {
        let now = Date()
        let interval = RepositoryViewModel.nextInactiveMonitorInterval(now: now, burstUntil: nil)
        XCTAssertEqual(interval, Constants.Timing.inactiveBackgroundMonitorIdleInterval)
    }

    @MainActor
    func testNextInactiveMonitorIntervalUsesBurstWhenBurstWindowActive() {
        let now = Date()
        let burstUntil = now.addingTimeInterval(30)
        let interval = RepositoryViewModel.nextInactiveMonitorInterval(now: now, burstUntil: burstUntil)
        XCTAssertEqual(interval, Constants.Timing.inactiveBackgroundMonitorBurstInterval)
    }

    @MainActor
    func testNextInactiveMonitorIntervalUsesIdleWhenBurstExpired() {
        let now = Date()
        let burstUntil = now.addingTimeInterval(-1)
        let interval = RepositoryViewModel.nextInactiveMonitorInterval(now: now, burstUntil: burstUntil)
        XCTAssertEqual(interval, Constants.Timing.inactiveBackgroundMonitorIdleInterval)
    }

    @MainActor
    func testMarkBackgroundRepoSignalSetsBurstDeadline() {
        let vm = RepositoryViewModel()
        let url = URL(fileURLWithPath: "/tmp/repo-bg-monitor")
        vm.backgroundRepoStates[url] = BackgroundRepoState(
            terminalTabs: [],
            activeTabID: nil,
            focusedSessionID: nil,
            fileWatcher: FileWatcher(),
            monitorTask: nil,
            burstUntil: nil
        )

        let now = Date()
        vm.markBackgroundRepoSignal(for: url, now: now)

        let burstUntil = vm.backgroundRepoStates[url]?.burstUntil
        XCTAssertNotNil(burstUntil)
        guard let burstUntil else { return }

        let expected = TimeInterval(Constants.Timing.inactiveBackgroundMonitorBurstWindow) / 1_000_000_000
        XCTAssertEqual(burstUntil.timeIntervalSince(now), expected, accuracy: 0.1)
    }

    // MARK: - Repository switch snapshots

    @MainActor
    func testApplyRepositorySnapshotIfFreshRestoresCoreState() {
        let vm = RepositoryViewModel()
        let repoURL = URL(fileURLWithPath: "/tmp/repo-snapshot-a")
        let baselineCommit = makeCommit(id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        let fileURL = repoURL.appendingPathComponent("README.md")

        vm.repositoryURL = repoURL
        vm.commitLimit = 700
        vm.focusedBranch = "main"
        vm.currentBranch = "main"
        vm.headShortHash = "aaaaaaaa"
        vm.commits = [baselineCommit]
        vm.selectedCommitID = baselineCommit.id
        vm.hasMoreCommits = true
        vm.uncommittedChanges = [" M README.md"]
        vm.uncommittedCount = 1
        vm.repositoryFiles = [FileItem(url: fileURL, isDirectory: false, children: nil)]
        vm.captureRepositorySnapshot(for: repoURL)

        vm.currentBranch = "other"
        vm.headShortHash = "-"
        vm.commits = []
        vm.selectedCommitID = nil
        vm.hasMoreCommits = false
        vm.uncommittedChanges = []
        vm.uncommittedCount = 0
        vm.repositoryFiles = []

        XCTAssertTrue(vm.applyRepositorySnapshotIfFresh(for: repoURL))
        XCTAssertEqual(vm.currentBranch, "main")
        XCTAssertEqual(vm.headShortHash, "aaaaaaaa")
        XCTAssertEqual(vm.commits.map(\.id), [baselineCommit.id])
        XCTAssertEqual(vm.selectedCommitID, baselineCommit.id)
        XCTAssertTrue(vm.hasMoreCommits)
        XCTAssertEqual(vm.uncommittedChanges, [" M README.md"])
        XCTAssertEqual(vm.uncommittedCount, 1)
        XCTAssertEqual(vm.repositoryFiles.map(\.id), [fileURL.path])
    }

    @MainActor
    func testApplyRepositorySnapshotIfFreshReturnsFalseWhenMissing() {
        let vm = RepositoryViewModel()
        let repoURL = URL(fileURLWithPath: "/tmp/repo-snapshot-missing")
        XCTAssertFalse(vm.applyRepositorySnapshotIfFresh(for: repoURL))
        XCTAssertFalse(vm.hasFreshRepositorySnapshot(for: repoURL))
    }

    // MARK: - lineWrap sync

    @MainActor
    func testSyncSettingsFromDefaultsDoesNotOverrideLineWrapWhenPreferenceIsUnset() {
        let vm = RepositoryViewModel()
        vm.isLineWrappingEnabled = true

        UserDefaults.standard.removeObject(forKey: lineWrapKey)
        vm.syncSettingsFromDefaults()

        XCTAssertTrue(vm.isLineWrappingEnabled)
    }

    @MainActor
    func testSyncSettingsFromDefaultsAppliesStoredLineWrapPreference() {
        let vm = RepositoryViewModel()
        vm.isLineWrappingEnabled = true

        UserDefaults.standard.set(false, forKey: lineWrapKey)
        vm.syncSettingsFromDefaults()

        XCTAssertFalse(vm.isLineWrappingEnabled)
    }

    @MainActor
    func testRestoreEditorSettingsAppliesStoredLineWrapPreference() {
        let vm = RepositoryViewModel()
        vm.isLineWrappingEnabled = true

        UserDefaults.standard.set(false, forKey: lineWrapKey)
        vm.restoreEditorSettings()

        XCTAssertFalse(vm.isLineWrappingEnabled)
    }

    @MainActor
    private func makeCommit(id: String) -> Commit {
        Commit(
            id: id,
            shortHash: String(id.prefix(8)),
            parents: [],
            author: "Tester",
            email: "test@example.com",
            date: Date(),
            subject: "snapshot baseline",
            decorations: [],
            lane: 0,
            nodeColorKey: 0,
            incomingLanes: [0],
            outgoingLanes: [0],
            laneColors: [LaneColor(lane: 0, colorKey: 0)],
            outgoingEdges: [LaneEdge(from: 0, to: 0, colorKey: 0)],
            insertions: nil,
            deletions: nil
        )
    }
}
