import Foundation
import SwiftUI

@Observable @MainActor
final class RepositoryViewModel {
    var repositoryURL: URL?
    var currentBranch: String = "-"
    var headShortHash: String = "-"
    var commits: [Commit] = [] {
        didSet { recalculateMaxLaneCount() }
    }
    var selectedCommitID: String?
    var commitDetails: String = "Selecione um commit para ver os detalhes."
    var branches: [String] = []
    var branchInfos: [BranchInfo] = []
    var branchTree: [BranchTreeNode] = []
    var focusedBranch: String?
    var inferBranchOrigins: Bool = true
    var hasMoreCommits: Bool = false
    var tags: [String] = []
    var stashes: [String] = []
    var selectedStash: String = ""
    var worktrees: [WorktreeItem] = []
    var statusMessage: String = "Selecione um repositorio para iniciar."
    var lastError: String?
    var isBusy: Bool = false
    var hasConflicts: Bool = false
    var isMerging: Bool = false
    var isRebasing: Bool = false
    var isCherryPicking: Bool = false
    var isGitRepository: Bool = true
    var uncommittedChanges: [String] = []
    var uncommittedCount: Int = 0
    var selectedChangeFile: String?
    var currentFileDiff: String = ""

    // Terminal — pane tree architecture
    var terminalTabs: [TerminalPaneNode] = []
    var activeTabID: UUID?
    var focusedSessionID: UUID?

    /// Flat list of all sessions across all tabs (backward compat + tab bar)
    var terminalSessions: [TerminalSession] {
        terminalTabs.flatMap { $0.allSessions() }
    }
    /// Points to the focused session within the active tab
    var activeTerminalID: UUID? {
        get { focusedSessionID }
        set { focusedSessionID = newValue }
    }

    // Clipboard
    let clipboardMonitor = ClipboardMonitor()
    @ObservationIgnored var terminalSendCallbacks: [UUID: (Data) -> Void] = [:]

    // Hunk diff state
    var currentFileDiffHunks: [DiffHunk] = []
    var selectedHunkLines: Set<UUID> = []

    // Blame state
    var isBlameVisible: Bool = false
    var blameEntries: [BlameEntry] = []
    @ObservationIgnored private var blameTask: Task<Void, Never>?

    // Reflog state
    var reflogEntries: [ReflogEntry] = []
    var isReflogVisible: Bool = false
    @ObservationIgnored private var reflogTask: Task<Void, Never>?

    // Interactive rebase state
    var isRebaseSheetVisible: Bool = false
    var rebaseItems: [RebaseItem] = []
    var rebaseBaseRef: String = ""

    // Navigation signal (consumed by ContentView to switch tabs)
    var navigateToGraphRequested: Bool = false

    // GitHub PR integration
    var pullRequests: [GitHubPRInfo] = []
    var isPRSheetVisible: Bool = false
    @ObservationIgnored let githubClient = GitHubClient()
    @ObservationIgnored let ntfyClient = NtfyClient()
    @ObservationIgnored private var prTask: Task<Void, Never>?

    // Branch review
    var isBranchReviewSheetVisible: Bool = false
    var branchReviewFindings: [ReviewFinding] = []
    var branchReviewSource: String = ""
    var branchReviewTarget: String = ""
    var isBranchReviewLoading: Bool = false
    var githubUsername: String = ""
    @ObservationIgnored private var lastNotifiedPRReviewIDs: Set<Int> = []

    // Code Review (Phase 3)
    var isCodeReviewVisible: Bool = false
    var codeReviewFiles: [CodeReviewFile] = []
    var selectedReviewFileID: UUID?
    var isCodeReviewLoading: Bool = false
    var codeReviewStats: CodeReviewStats = CodeReviewStats(totalFiles: 0, totalAdditions: 0, totalDeletions: 0, commitCount: 0, criticalCount: 0, warningCount: 0, suggestionCount: 0)
    @ObservationIgnored private var codeReviewTask: Task<Void, Never>?

    // PR Review Queue (Phase 4)
    var prReviewQueue: [PRReviewItem] = []
    @ObservationIgnored private var prPollingTask: Task<Void, Never>?

    // Diff Explanation (Phase 2)
    var currentDiffExplanation: DiffExplanation?
    var isExplainingDiff: Bool = false
    @ObservationIgnored private var explainDiffTask: Task<Void, Never>?

    // Auto-explain setting (reads UserDefaults)
    var autoExplainDiffs: Bool {
        get { UserDefaults.standard.bool(forKey: "zion.autoExplainDiffs") }
        set { UserDefaults.standard.set(newValue, forKey: "zion.autoExplainDiffs") }
    }
    var diffExplanationDepth: DiffExplanationDepth {
        get { DiffExplanationDepth(rawValue: UserDefaults.standard.string(forKey: "zion.diffExplanationDepth") ?? "quick") ?? .quick }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "zion.diffExplanationDepth") }
    }

    // Submodule state
    var submodules: [SubmoduleInfo] = []

    // AI commit message
    var suggestedCommitMessage: String = ""
    var isGeneratingAIMessage: Bool = false
    var aiQuotaExceeded: Bool = false
    var aiDiffExplanation: String = ""

    // AI Smart Services
    var aiConflictResolution: String = ""
    var aiReviewFindings: [ReviewFinding] = []
    var isReviewVisible: Bool = false
    var aiChangelog: String = ""
    var isChangelogSheetVisible: Bool = false
    var changelogFromRef: String = ""
    var changelogToRef: String = "HEAD"
    var aiSemanticSearchResults: [String] = []
    var isSemanticSearchActive: Bool = false
    var branchSummaries: [String: String] = [:]
    var aiBlameExplanation: String = ""
    var aiBlameEntryID: UUID?
    var aiCommitSplitSuggestions: [CommitSuggestion] = []
    var isSplitVisible: Bool = false
    var aiProvider: AIProvider = .none {
        didSet { 
            UserDefaults.standard.set(aiProvider.rawValue, forKey: "zion.aiProvider")
            aiQuotaExceeded = false // Reset on provider change
            _aiKeyRevision += 1 // Ensure aiAPIKey getter is re-evaluated for the new provider
        }
    }
    var commitMessageStyle: CommitMessageStyle = .compact {
        didSet { UserDefaults.standard.set(commitMessageStyle.rawValue, forKey: "zion.commitMessageStyle") }
    }
    @ObservationIgnored let aiClient = AIClient()
    @ObservationIgnored private var aiTask: Task<Void, Never>?

    @ObservationIgnored private var _cachedAIKey: String?
    @ObservationIgnored private var _cachedAIKeyProvider: AIProvider?
    private var _aiKeyRevision: Int = 0
    var aiAPIKey: String {
        get {
            let _ = _aiKeyRevision // Register dependency
            if _cachedAIKeyProvider == aiProvider, let cached = _cachedAIKey {
                return cached
            }
            let key = AIClient.loadAPIKey(for: aiProvider) ?? ""
            _cachedAIKey = key
            _cachedAIKeyProvider = aiProvider
            return key
        }
        set {
            if newValue.isEmpty {
                AIClient.deleteAPIKey(for: aiProvider)
            } else {
                AIClient.saveAPIKey(newValue, for: aiProvider)
            }
            _cachedAIKey = newValue
            _cachedAIKeyProvider = aiProvider
            _aiKeyRevision += 1 // Trigger observation
        }
    }

    var isAIConfigured: Bool {
        aiProvider != .none && !aiAPIKey.isEmpty
    }

    // Commit signing
    var commitSignatureStatus: [String: String] = [:] // hash -> "G"/"N"/"B"/etc

    // Background fetch
    var behindRemoteCount: Int = 0
    @ObservationIgnored private var backgroundFetchTask: Task<Void, Never>?
    @ObservationIgnored private var lastNotifiedBehindCount: Int = 0
    @ObservationIgnored private var notifiedReviewRequestPRIDs: Set<Int> = []

    // ntfy Push Notifications
    var ntfyTopic: String = "" {
        didSet {
            UserDefaults.standard.set(ntfyTopic, forKey: "zion.ntfy.topic")
            if !ntfyTopic.isEmpty {
                NtfyClient.writeGlobalConfig(topic: ntfyTopic, serverURL: ntfyServerURL)
            }
        }
    }
    var ntfyServerURL: String = "https://ntfy.sh" {
        didSet {
            UserDefaults.standard.set(ntfyServerURL, forKey: "zion.ntfy.serverURL")
            if !ntfyTopic.isEmpty {
                NtfyClient.writeGlobalConfig(topic: ntfyTopic, serverURL: ntfyServerURL)
            }
        }
    }
    var ntfyEnabledEvents: [String] = NtfyEvent.defaultEnabledEvents {
        didSet { UserDefaults.standard.set(ntfyEnabledEvents, forKey: "zion.ntfy.enabledEvents") }
    }
    var ntfyExternalAgentsEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(ntfyExternalAgentsEnabled, forKey: "zion.ntfy.externalAgents")
            syncAIAgentConfigs()
        }
    }
    var ntfySelectedAgents: [String] = [] {
        didSet {
            UserDefaults.standard.set(ntfySelectedAgents, forKey: "zion.ntfy.selectedAgents")
            syncAIAgentConfigs()
        }
    }

    var ntfyLocalNotificationsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "zion.ntfy.localNotifications") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "zion.ntfy.localNotifications") }
    }

    var isNtfyConfigured: Bool { !ntfyTopic.isEmpty }

    // Background repo persistence (terminal sessions + change badges)
    @ObservationIgnored private var backgroundRepoStates: [URL: BackgroundRepoState] = [:]
    var backgroundRepoChangedFiles: [URL: Int] = [:]

    // Repository statistics
    var repoStats: RepositoryStats?
    var isGitAvailable: Bool = true

    // Conflict resolution state
    var conflictedFiles: [ConflictFile] = []
    var selectedConflictFile: String?
    var conflictBlocks: [ConflictBlock] = []
    var isConflictViewVisible: Bool = false
    @ObservationIgnored private var conflictTask: Task<Void, Never>?

    // Clone state
    var isCloneSheetVisible: Bool = false
    var cloneProgress: String = ""
    var isCloning: Bool = false
    var cloneError: String?
    @ObservationIgnored private var cloneTask: Task<Void, Never>?
    @ObservationIgnored private var cloneProcess: Process?

    // Zion Code state
    var repositoryFiles: [FileItem] = [] {
        didSet { rebuildFlatFileCache() }
    }
    var openedFiles: [FileItem] = []
    var activeFileID: String?
    var selectedCodeFile: FileItem?
    var codeFileContent: String = "" {
        didSet { markCurrentFileUnsavedIfChanged() }
    }
    var expandedPaths: Set<String> = []

    // Tracking unsaved changes per file
    var unsavedFiles: Set<String> = []
    @ObservationIgnored private var originalFileContents: [String: String] = [:]

    // Editor Settings (persisted via UserDefaults)
    var selectedTheme: EditorTheme = .dracula {
        didSet { UserDefaults.standard.set(selectedTheme.rawValue, forKey: "editor.theme") }
    }
    var editorFontSize: Double = 13.0 {
        didSet { UserDefaults.standard.set(editorFontSize, forKey: "editor.fontSize") }
    }
    var editorFontFamily: String = "SF Mono" {
        didSet { UserDefaults.standard.set(editorFontFamily, forKey: "editor.fontFamily") }
    }
    var editorLineSpacing: Double = 1.2 {
        didSet { UserDefaults.standard.set(editorLineSpacing, forKey: "editor.lineSpacing") }
    }
    var isLineWrappingEnabled: Bool = true {
        didSet { UserDefaults.standard.set(isLineWrappingEnabled, forKey: "editor.lineWrap") }
    }

    // Terminal font settings
    var terminalFontSize: Double = 13.0 {
        didSet { UserDefaults.standard.set(terminalFontSize, forKey: "terminal.fontSize") }
    }
    var terminalFontFamily: String = "SF Mono" {
        didSet { UserDefaults.standard.set(terminalFontFamily, forKey: "terminal.fontFamily") }
    }
    var isTerminalFontAvailable: Bool {
        NSFont(name: terminalFontFamily, size: 13) != nil
    }

    var branchInput: String = ""
    var tagInput: String = ""
    var stashMessageInput: String = ""
    var cherryPickInput: String = ""
    var resetTargetInput: String = "HEAD~1"
    var rebaseTargetInput: String = ""
    var worktreePathInput: String = ""
    var worktreeBranchInput: String = ""
    var remotes: [RemoteInfo] = []
    var remoteNameInput: String = "origin"
    var remoteURLInput: String = ""
    var commitMessageInput: String = ""
    var amendLastCommit: Bool = false
    var isTypingQuickly: Bool = false
    var shouldClosePopovers: Bool = false
    @ObservationIgnored private let logger = DiagnosticLogger.shared

    private var recentReposData: Data {
        get { UserDefaults.standard.data(forKey: "zion.recentRepositories") ?? Data() }
        set { UserDefaults.standard.set(newValue, forKey: "zion.recentRepositories") }
    }
    var recentRepositories: [URL] = []

    // Performance caches
    private(set) var maxLaneCount: Int = 1
    private(set) var flatFileCache: [FileItem] = []

    @ObservationIgnored private let git = GitClient()
    @ObservationIgnored private let worker = RepositoryWorker()
    @ObservationIgnored private let fileWatcher = FileWatcher()

    @ObservationIgnored private let defaultCommitLimitAll = 700
    @ObservationIgnored private let defaultCommitLimitFocused = 450
    @ObservationIgnored private let commitPageSize = 300
    @ObservationIgnored private let maxCommitLimit = 5000
    @ObservationIgnored private var commitLimit = 700
    @ObservationIgnored private var refreshRequestID = UUID()
    @ObservationIgnored private var detailsRequestID = UUID()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var detailsTask: Task<Void, Never>?
    @ObservationIgnored private var actionTask: Task<Void, Never>?
    @ObservationIgnored private var autoRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var cachedIgnoredPaths: Set<String>?

    func checkGitAvailability() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["git"]
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            isGitAvailable = (process.terminationStatus == 0)
        } catch {
            isGitAvailable = false
        }
    }

    // Restore persisted editor settings from UserDefaults
    func restoreEditorSettings() {
        checkGitAvailability()
        
        let defaults = UserDefaults.standard
        if let themeRaw = defaults.string(forKey: "editor.theme"),
           let theme = EditorTheme(rawValue: themeRaw) {
            selectedTheme = theme
        }
        if defaults.object(forKey: "editor.fontSize") != nil {
            editorFontSize = defaults.double(forKey: "editor.fontSize")
        }
        if let family = defaults.string(forKey: "editor.fontFamily") {
            editorFontFamily = family
        }
        if defaults.object(forKey: "editor.lineSpacing") != nil {
            editorLineSpacing = defaults.double(forKey: "editor.lineSpacing")
        }
        if defaults.object(forKey: "editor.lineWrap") != nil {
            isLineWrappingEnabled = defaults.bool(forKey: "editor.lineWrap")
        }
        // Terminal font settings
        if defaults.object(forKey: "terminal.fontSize") != nil {
            terminalFontSize = defaults.double(forKey: "terminal.fontSize")
        }
        if let family = defaults.string(forKey: "terminal.fontFamily") {
            terminalFontFamily = family
        }
        // AI provider
        if let aiRaw = defaults.string(forKey: "zion.aiProvider"),
           let provider = AIProvider(rawValue: aiRaw) {
            aiProvider = provider
        }
        // Commit message style
        if let styleRaw = defaults.string(forKey: "zion.commitMessageStyle"),
           let style = CommitMessageStyle(rawValue: styleRaw) {
            commitMessageStyle = style
        }
        // ntfy Push Notifications
        if let topic = defaults.string(forKey: "zion.ntfy.topic") {
            ntfyTopic = topic
        } else if let global = NtfyClient.readGlobalConfig() {
            ntfyTopic = global.topic
            ntfyServerURL = global.serverURL
        }
        if let server = defaults.string(forKey: "zion.ntfy.serverURL"), !server.isEmpty {
            ntfyServerURL = server
        }
        if let events = defaults.stringArray(forKey: "zion.ntfy.enabledEvents") {
            ntfyEnabledEvents = events
        }
        if defaults.object(forKey: "zion.ntfy.externalAgents") != nil {
            ntfyExternalAgentsEnabled = defaults.bool(forKey: "zion.ntfy.externalAgents")
        }
        if let agents = defaults.stringArray(forKey: "zion.ntfy.selectedAgents") {
            ntfySelectedAgents = agents
        }
    }

    // MARK: - ntfy Helpers

    func testNtfyNotification() async {
        let success = await ntfyClient.sendTest(serverURL: ntfyServerURL, topic: ntfyTopic)
        if !success {
            lastError = L10n("ntfy.test.failed")
        }
    }

    func notifyPRCreated(title: String, url: String) {
        let repoName = repositoryURL?.lastPathComponent ?? ""
        Task {
            await ntfyClient.sendIfEnabled(
                event: .prCreated,
                title: L10n("ntfy.event.prCreated"),
                body: "\(title)\n\(url)",
                repoName: repoName
            )
        }
    }

    func syncAIAgentConfigs() {
        guard let repoPath = repositoryURL else { return }
        let selectedAgents = ntfySelectedAgents.compactMap { AIAgent(rawValue: $0) }

        if ntfyExternalAgentsEnabled && isNtfyConfigured && !selectedAgents.isEmpty {
            AIAgentConfigManager.updateNtfyBlock(
                agents: selectedAgents,
                topic: ntfyTopic,
                serverURL: ntfyServerURL,
                repoPath: repoPath
            )
        } else {
            // Remove from all agents when disabled
            AIAgentConfigManager.removeNtfyBlock(agents: AIAgent.allCases, repoPath: repoPath)
        }
    }

    private func recalculateMaxLaneCount() {
        let maxLane = commits
            .flatMap { [$0.lane] + $0.incomingLanes + $0.outgoingLanes + $0.outgoingEdges.map(\.to) }
            .max() ?? 0
        maxLaneCount = maxLane + 1
    }

    func openRepository(_ url: URL) {
        let previousURL = repositoryURL

        // Same repo already open — just refresh metadata, don't touch terminals
        if previousURL == url {
            logger.log(.info, "openRepository SKIP (same repo)", context: "\(url.lastPathComponent) tabs=\(terminalTabs.count) sessions=\(terminalTabs.flatMap { $0.allSessions() }.count)", source: #function)
            saveRecentRepository(url)
            refreshRepository()
            refreshFileTree()
            loadPullRequests()
            loadSubmodules()
            return
        }

        repositoryURL = url
        saveRecentRepository(url)
        commitLimit = defaultCommitLimit(for: nil)
        if worktreePathInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            worktreePathInput = url.deletingLastPathComponent().appendingPathComponent("new-worktree").path
        }

        let stashedKeys = backgroundRepoStates.keys.map { $0.lastPathComponent }
        logger.log(.info, "openRepository ENTER", context: "prev=\(previousURL?.lastPathComponent ?? "nil") target=\(url.lastPathComponent) tabs=\(terminalTabs.count) sessions=\(terminalTabs.flatMap { $0.allSessions() }.count) stashed=\(stashedKeys)", source: #function)

        // Stash current repo's terminals (save WITHOUT clearing terminalTabs yet to avoid
        // intermediate empty state that could cause SwiftUI to dismantle NSViews prematurely)
        if let previousURL, !terminalTabs.isEmpty {
            let sessions = terminalTabs.flatMap { $0.allSessions() }
            logger.log(.info, "STASH", context: "\(previousURL.lastPathComponent): \(terminalTabs.count) tabs, \(sessions.map { "\($0.label)(\($0.id.uuidString.prefix(4))) alive=\($0.isAlive) preserve=\($0._shouldPreserve) pid=\($0._shellPid)" })", source: #function)
            let watcher = FileWatcher()
            backgroundRepoStates[previousURL] = BackgroundRepoState(
                terminalTabs: terminalTabs,
                activeTabID: activeTabID,
                focusedSessionID: focusedSessionID,
                fileWatcher: watcher,
                monitorTask: nil
            )
            backgroundRepoChangedFiles[previousURL] = 0
            startBackgroundMonitor(for: previousURL)
            // DON'T set terminalTabs = [] here — let the restore/create below do a direct swap
        } else if previousURL == nil {
            // First open — no previous repo, kill any leftover terminals
            logger.log(.info, "KILL (first open)", context: "tabs=\(terminalTabs.count)", source: #function)
            for tab in terminalTabs {
                for session in tab.allSessions() {
                    session.killCachedProcess()
                }
            }
        }

        // Restore stashed terminals or create fresh (direct swap, no empty intermediate)
        if let restored = backgroundRepoStates.removeValue(forKey: url) {
            restored.fileWatcher.stop()
            restored.monitorTask?.cancel()
            let sessions = restored.terminalTabs.flatMap { $0.allSessions() }
            logger.log(.info, "RESTORE", context: "\(url.lastPathComponent): \(restored.terminalTabs.count) tabs, \(sessions.map { "\($0.label)(\($0.id.uuidString.prefix(4))) alive=\($0.isAlive) preserve=\($0._shouldPreserve) pid=\($0._shellPid)" })", source: #function)
            terminalTabs = restored.terminalTabs
            activeTabID = restored.activeTabID
            focusedSessionID = restored.focusedSessionID
            backgroundRepoChangedFiles.removeValue(forKey: url)
            // Reset isAlive for sessions that died while stashed — lets updateNSView restart them
            for tab in terminalTabs {
                for session in tab.allSessions() where !session.isAlive {
                    session.isAlive = true
                }
            }
        } else {
            let stashedKeysNow = backgroundRepoStates.keys.map { $0.lastPathComponent }
            logger.log(.info, "FRESH (no stash found)", context: "\(url.lastPathComponent) stashedKeys=\(stashedKeysNow)", source: #function)
            terminalTabs = []
            activeTabID = nil
            focusedSessionID = nil
            createDefaultTerminalSession(repositoryURL: url, branchName: currentBranch.isEmpty ? url.lastPathComponent : currentBranch)
        }

        let finalStashedKeys = backgroundRepoStates.keys.map { $0.lastPathComponent }
        logger.log(.info, "openRepository EXIT", context: "tabs=\(terminalTabs.count) sessions=\(terminalTabs.flatMap { $0.allSessions() }.count) stashed=\(finalStashedKeys)", source: #function)

        openedFiles.removeAll()
        activeFileID = nil
        selectedCodeFile = nil

        refreshRepository()
        refreshFileTree()
        startAutoRefreshTimer()
        startFileWatcher(for: url)
        loadPullRequests()
        loadSubmodules()
        startBackgroundFetch()
        loadSignatureStatuses()
    }

    func cloneRepository(remoteURL: String, destination: URL) {
        guard !isCloning else { return }
        isCloning = true
        cloneProgress = ""
        cloneError = nil

        cloneTask = Task.detached { [worker] in
            do {
                let process = try worker.cloneRepository(
                    remoteURL: remoteURL,
                    destination: destination
                ) { line in
                    Task { @MainActor [weak self] in
                        self?.cloneProgress = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }

                await MainActor.run { [weak self] in
                    self?.cloneProcess = process
                }

                process.waitUntilExit()

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.cloneProcess = nil
                    if process.terminationStatus == 0 {
                        self.isCloning = false
                        self.isCloneSheetVisible = false
                        self.cloneProgress = ""
                        self.openRepository(destination)
                        Task {
                            await self.ntfyClient.sendIfEnabled(
                                event: .cloneComplete,
                                title: L10n("ntfy.event.cloneComplete"),
                                body: destination.lastPathComponent,
                                repoName: destination.lastPathComponent
                            )
                        }
                    } else {
                        self.isCloning = false
                        self.cloneError = self.cloneProgress.isEmpty
                            ? "Clone failed (exit code \(process.terminationStatus))"
                            : self.cloneProgress
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.isCloning = false
                    self?.cloneError = error.localizedDescription
                }
            }
        }
    }

    func cancelClone() {
        cloneProcess?.terminate()
        cloneProcess = nil
        cloneTask?.cancel()
        cloneTask = nil
        isCloning = false
        cloneProgress = ""
        cloneError = nil
    }

    func loadRecentRepositories() {
        if let urls = try? JSONDecoder().decode([URL].self, from: recentReposData) {
            recentRepositories = urls
        }
    }

    private func saveRecentRepository(_ url: URL) {
        var current = (try? JSONDecoder().decode([URL].self, from: recentReposData)) ?? []
        current.removeAll { $0 == url }
        current.insert(url, at: 0)
        let limited = Array(current.prefix(5))
        if let encoded = try? JSONEncoder().encode(limited) {
            recentReposData = encoded
            recentRepositories = limited
        }
    }

    func refreshRepository() {
        refreshRepository(setBusy: true)
    }

    func selectCommit(_ commitID: String?) {
        selectedCommitID = commitID
        loadCommitDetails(for: commitID)
    }

    func selectChangeFile(_ file: String?) {
        selectedChangeFile = file
        if let file {
            loadDiff(for: file)
        } else {
            currentFileDiff = ""
        }
    }

    // MARK: - Zion Code Methods

    func refreshFileTree() {
        guard let url = repositoryURL else { return }
        Task {
            // Phase 1: load top-level only (instant)
            let initial = await loadFiles(at: url, ignoredPaths: nil, maxDepth: 0)
            repositoryFiles = initial
            reloadExpandedDirectories()

            // Phase 2: refine with gitignore
            let ignoredPaths = await loadGitIgnoredPaths()
            if !ignoredPaths.isEmpty {
                cachedIgnoredPaths = ignoredPaths
                let filtered = await loadFiles(at: url, ignoredPaths: ignoredPaths, maxDepth: 0)
                repositoryFiles = filtered
                reloadExpandedDirectories()
            }
        }
    }

    private func reloadExpandedDirectories() {
        for path in expandedPaths {
            loadChildrenIfNeeded(for: path)
        }
    }

    private func loadChildrenIfNeeded(for path: String) {
        guard let item = findItem(path: path, in: repositoryFiles),
              item.isDirectory, item.children == nil else { return }
        let itemURL = item.url
        let ignoredPaths = cachedIgnoredPaths
        Task {
            let children = await loadFiles(at: itemURL, ignoredPaths: ignoredPaths, maxDepth: 0)
            repositoryFiles = updateTree(repositoryFiles, path: path, newChildren: children)
        }
    }

    private func findItem(path: String, in items: [FileItem]) -> FileItem? {
        for item in items {
            if item.id == path { return item }
            if let children = item.children,
               let found = findItem(path: path, in: children) {
                return found
            }
        }
        return nil
    }

    private func updateTree(_ items: [FileItem], path: String, newChildren: [FileItem]) -> [FileItem] {
        items.map { item in
            if item.id == path {
                return FileItem(url: item.url, isDirectory: item.isDirectory, children: newChildren)
            }
            if let children = item.children {
                return FileItem(url: item.url, isDirectory: item.isDirectory,
                              children: updateTree(children, path: path, newChildren: newChildren))
            }
            return item
        }
    }

    private static let ignoredDirectories: Set<String> = [
        "node_modules", ".build", ".git", "dist", "__pycache__", ".next", "build",
        ".swiftpm", ".DS_Store", "Pods", ".gradle", ".idea", ".vscode",
        "DerivedData", ".cache", "vendor", ".eggs", "*.egg-info",
        ".tox", ".mypy_cache", ".pytest_cache", "coverage", ".nuxt",
        ".output", ".turbo", ".vercel", ".expo"
    ]

    private func loadGitIgnoredPaths() async -> Set<String> {
        guard let url = repositoryURL else { return [] }
        do {
            let output = try await worker.runAction(
                args: ["ls-files", "--others", "--ignored", "--exclude-standard", "--directory"],
                in: url
            )
            let paths = output.split(separator: "\n").map {
                // git outputs paths relative to repo root, trailing / for dirs
                url.appendingPathComponent(String($0).trimmingCharacters(in: CharacterSet(charactersIn: "/"))).path
            }
            return Set(paths)
        } catch {
            logger.log(.warn, "Failed to load gitignored paths: \(error.localizedDescription)", source: #function)
            return []
        }
    }

    private func loadFiles(at url: URL, ignoredPaths: Set<String>? = nil, maxDepth: Int = .max) async -> [FileItem] {
        let fm = FileManager.default
        do {
            let contents = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            var items: [FileItem] = []
            for item in contents {
                let name = item.lastPathComponent

                // Skip hardcoded ignored directories
                if Self.ignoredDirectories.contains(name) { continue }

                // Skip git-ignored paths
                if let ignored = ignoredPaths, ignored.contains(item.path) { continue }

                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let children: [FileItem]?
                if isDir && maxDepth > 0 {
                    children = await loadFiles(at: item, ignoredPaths: ignoredPaths, maxDepth: maxDepth - 1)
                } else if isDir {
                    children = nil // Directory but children not loaded yet (lazy)
                } else {
                    children = nil
                }
                items.append(FileItem(url: item, isDirectory: isDir, children: children?.sorted(by: { $0.name.lowercased() < $1.name.lowercased() })))
            }
            return items.sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.lowercased() < b.name.lowercased()
            }
        } catch {
            logger.log(.warn, "Failed to load files: \(error.localizedDescription)", context: url.path, source: #function)
            return []
        }
    }

    func selectCodeFile(_ item: FileItem) {
        guard !item.isDirectory else { return }

        // Add to opened files if not already there
        if !openedFiles.contains(where: { $0.id == item.id }) {
            openedFiles.append(item)
        }

        activeFileID = item.id
        selectedCodeFile = item

        let itemURL = item.url
        let itemID = item.id
        Task {
            do {
                let content = try String(contentsOf: itemURL, encoding: .utf8)
                codeFileContent = content
                originalFileContents[itemID] = content
            } catch {
                codeFileContent = "Erro ao ler arquivo: \(error.localizedDescription)"
            }
        }
    }

    func markCurrentFileUnsavedIfChanged() {
        guard let fileID = activeFileID else { return }
        if let original = originalFileContents[fileID], original != codeFileContent {
            unsavedFiles.insert(fileID)
        } else {
            unsavedFiles.remove(fileID)
        }
    }

    func closeFile(id: String) {
        guard let index = openedFiles.firstIndex(where: { $0.id == id }) else { return }
        
        openedFiles.remove(at: index)
        
        if activeFileID == id {
            if let last = openedFiles.last {
                selectCodeFile(last)
            } else {
                activeFileID = nil
                selectedCodeFile = nil
                codeFileContent = ""
            }
        }
    }

    func saveCurrentCodeFile() {
        guard let file = selectedCodeFile else { return }
        let content = codeFileContent
        let fileURL = file.url
        let fileID = file.id
        let fileName = file.name
        Task {
            do {
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                statusMessage = String(format: L10n("Arquivo salvo: %@"), fileName)
                originalFileContents[fileID] = content
                unsavedFiles.remove(fileID)
                refreshRepository()
            } catch {
                handleError(error)
            }
        }
    }

    func allFlatFiles() -> [FileItem] {
        flatFileCache
    }

    private func rebuildFlatFileCache() {
        func flatten(_ items: [FileItem]) -> [FileItem] {
            var result: [FileItem] = []
            for item in items {
                if item.isDirectory {
                    if let children = item.children {
                        result.append(contentsOf: flatten(children))
                    }
                } else {
                    result.append(item)
                }
            }
            return result
        }
        flatFileCache = flatten(repositoryFiles)
    }

    func toggleExpansion(for path: String) {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
        } else {
            expandedPaths.insert(path)
            loadChildrenIfNeeded(for: path)
        }
    }

    func fetch() { runGitAction(label: "Fetch", args: ["fetch", "--all", "--prune"]) }
    func pull() { runGitAction(label: "Pull", args: ["pull", "--ff-only"]) }
    func push() {
        let branch = currentBranch ?? ""
        let hasUpstream = branchInfos.first(where: { !$0.isRemote && $0.name == branch })?.upstream.isEmpty == false
        if hasUpstream {
            runGitAction(label: "Push", args: ["push"])
        } else if !branch.isEmpty {
            let remote = remotes.first?.name ?? "origin"
            runGitAction(label: "Push", args: ["push", "--set-upstream", remote, branch])
        } else {
            runGitAction(label: "Push", args: ["push"])
        }
    }


    func setBranchFocus(_ branch: String?) {
        let normalized = branch?.clean
        focusedBranch = normalized?.isEmpty == true ? nil : normalized
        commitLimit = defaultCommitLimit(for: focusedBranch)
        refreshCommitsOnly()
    }

    func loadMoreCommits() {
        guard repositoryURL != nil, hasMoreCommits else { return }
        let nextLimit = min(maxCommitLimit, commitLimit + commitPageSize)
        guard nextLimit != commitLimit else { return }
        commitLimit = nextLimit
        refreshCommitsOnly()
    }

    func checkout(reference: String) {
        let target = reference.clean
        guard !target.isEmpty else { return }

        // Determine local branch name if it's a remote ref
        var localName = target
        for remote in remotes {
            if target.hasPrefix("\(remote.name)/") {
                localName = String(target.dropFirst(remote.name.count + 1))
                break
            }
        }

        if localBranchExists(named: localName) {
            runGitAction(label: "Checkout", args: ["checkout", localName])
        } else if isRemoteRefName(target) {
            runGitAction(label: "Checkout", args: ["checkout", "-t", target])
        } else {
            runGitAction(label: "Checkout", args: ["checkout", target])
        }
    }

    func checkoutAndPull(reference: String) {
        let target = reference.clean
        guard !target.isEmpty else { return }
        
        actionTask?.cancel()
        isBusy = true
        
        let url = repositoryURL
        actionTask = Task {
            do {
                guard let url else { return }
                
                // 1. Determine local branch name and full remote target
                var localName = target
                var remoteTarget = target
                
                // Check if target is a known remote branch (e.g. origin/develop)
                for remote in remotes {
                    if target.hasPrefix("\(remote.name)/") {
                        localName = String(target.dropFirst(remote.name.count + 1))
                        remoteTarget = target
                        break
                    }
                }
                
                // 2. Perform Smart Checkout
                if localBranchExists(named: localName) {
                    // Already exists locally, just checkout and pull
                    let _ = try await worker.runAction(args: ["checkout", localName], in: url)
                } else if isRemoteRefName(remoteTarget) {
                    // New local branch tracking remote
                    let _ = try await worker.runAction(args: ["checkout", "-t", remoteTarget], in: url)
                } else {
                    // Fallback
                    let _ = try await worker.runAction(args: ["checkout", target], in: url)
                }
                
                // 3. Pull changes
                let _ = try await worker.runAction(args: ["pull"], in: url)
                
                clearError()
                statusMessage = L10n("Checkout e Pull concluídos para %@", localName)
                refreshRepository(setBusy: true)
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    func pushBranch(_ branch: String, to remote: String, setUpstream: Bool, mode: PushMode) {
        let branchName = branch.clean
        let remoteName = remote.clean
        guard !branchName.isEmpty, !remoteName.isEmpty else { return }

        var args = ["push"]
        if setUpstream {
            args.append("--set-upstream")
        }
        switch mode {
        case .normal:
            break
        case .forceWithLease:
            args.append("--force-with-lease")
        case .force:
            args.append("--force")
        }
        args.append(remoteName)
        args.append("\(branchName):\(branchName)")
        runGitAction(label: "Push branch", args: args)
    }

    func checkoutBranch() {
        let target = branchInput.clean
        guard !target.isEmpty else { return }
        checkout(reference: target)
    }

    func createBranch() {
        let target = branchInput.clean
        guard !target.isEmpty else { return }
        createBranch(named: target, from: "HEAD", andCheckout: true)
    }

    func createBranch(named name: String, from startPoint: String, andCheckout: Bool = true) {
        let targetName = name.clean
        let targetPoint = startPoint.clean
        guard !targetName.isEmpty, !targetPoint.isEmpty else { return }
        if andCheckout {
            runGitAction(label: "Nova branch", args: ["checkout", "-b", targetName, targetPoint])
        } else {
            runGitAction(label: "Nova branch", args: ["branch", targetName, targetPoint])
        }
    }

    func mergeBranch() {
        let target = branchInput.clean
        guard !target.isEmpty else { return }
        mergeBranch(named: target)
    }

    func mergeBranch(named branch: String) {
        let target = branch.clean
        guard !target.isEmpty else { return }
        runGitAction(label: "Merge", args: ["merge", target])
    }

    func pullIntoCurrent(fromRemoteBranch remoteBranch: String) {
        let target = remoteBranch.clean
        guard !target.isEmpty else { return }
        let components = target.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
        guard components.count == 2 else { return }
        runGitAction(label: "Pull branch", args: ["pull", String(components[0]), String(components[1])])
    }

    func deleteRemoteBranch(reference: String) {
        let target = reference.clean
        guard isRemoteRefName(target) else { return }
        let parts = target.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return }
        runGitAction(label: "Delete remote branch", args: ["push", String(parts[0]), "--delete", String(parts[1])])
    }

    func renameBranch(oldName: String, newName: String) {
        let old = oldName.clean
        let new = newName.clean
        guard !old.isEmpty, !new.isEmpty else { return }
        runGitAction(label: "Renomear branch", args: ["branch", "-m", old, new])
    }

    func rebaseOntoTarget() {
        let target = rebaseTargetInput.clean
        guard !target.isEmpty else { return }
        runGitAction(label: "Rebase", args: ["rebase", target])
    }

    func rebaseCurrentBranch(onto reference: String) {
        let target = reference.clean
        guard !target.isEmpty else { return }
        runGitAction(label: "Rebase", args: ["rebase", target])
    }

    func cherryPick() {
        let target = cherryPickInput.clean
        guard !target.isEmpty else { return }
        cherryPick(commitHash: target)
    }

    func cherryPick(commitHash: String) {
        let target = commitHash.clean
        guard !target.isEmpty else { return }
        runGitAction(label: "Cherry-pick", args: ["cherry-pick", target])
    }

    func revert(commitHash: String) {
        let target = commitHash.clean
        guard !target.isEmpty else { return }
        runGitAction(label: "Revert", args: ["revert", "--no-edit", target])
    }

    func hardReset() {
        let target = resetTargetInput.clean
        guard !target.isEmpty else { return }
        hardReset(to: target)
    }

    func hardReset(to target: String) {
        let cleanedTarget = target.clean
        guard !cleanedTarget.isEmpty else { return }
        runGitAction(label: "Reset --hard", args: ["reset", "--hard", cleanedTarget])
    }

    func resetToCommit(_ commitID: String, hard: Bool) {
        let args = hard ? ["reset", "--hard", commitID] : ["reset", "--soft", commitID]
        runGitAction(label: hard ? "Reset --hard" : "Reset --soft", args: args)
    }

    func discardChanges(in path: String) {
        let file = path.trimmingCharacters(in: .whitespaces)
        runGitAction(label: "Discard", args: ["checkout", "--", file])
    }

    func createTag() {
        let target = tagInput.clean
        guard !target.isEmpty else { return }
        createTag(named: target, at: "HEAD")
    }

    func createTag(named name: String, at target: String) {
        let tagName = name.clean
        let tagTarget = target.clean
        guard !tagName.isEmpty, !tagTarget.isEmpty else { return }
        runGitAction(label: "Criar tag", args: ["tag", tagName, tagTarget])
    }

    func deleteTag() {
        let target = tagInput.clean
        guard !target.isEmpty else { return }
        runGitAction(label: "Remover tag", args: ["tag", "-d", target])
    }

    func createStash() {
        let message = stashMessageInput.clean
        createStash(message: message.isEmpty ? nil : message)
    }

    func createStash(message: String?) {
        let cleanedMessage = message?.clean ?? ""
        if cleanedMessage.isEmpty {
            runGitAction(label: "Stash", args: ["stash", "push"])
        } else {
            runGitAction(label: "Stash", args: ["stash", "push", "-m", cleanedMessage])
        }
    }

    func applySelectedStash() {
        Task {
            let ref = await resolveStashReference(selectedStash)
            guard let ref else { return }
            runGitAction(label: "Apply stash", args: ["stash", "apply", ref])
        }
    }

    func popSelectedStash() {
        Task {
            let ref = await resolveStashReference(selectedStash)
            guard let ref else { return }
            runGitAction(label: "Pop stash", args: ["stash", "pop", ref])
        }
    }

    func dropSelectedStash() {
        Task {
            let ref = await resolveStashReference(selectedStash)
            guard let ref else { return }
            runGitAction(label: "Drop stash", args: ["stash", "drop", ref])
        }
    }

    func addWorktree() {
        let path = worktreePathInput.clean
        guard !path.isEmpty else { return }

        let branch = worktreeBranchInput.clean
        addWorktree(path: path, branch: branch.isEmpty ? nil : branch)
    }

    func addWorktree(path: String, branch: String?) {
        let cleanedPath = path.clean
        guard !cleanedPath.isEmpty else { return }

        var args = ["worktree", "add", cleanedPath]
        if let branch, !branch.clean.isEmpty {
            args.append(branch.clean)
        }
        runGitAction(label: "Adicionar worktree", args: args)
    }

    func removeWorktree(_ path: String) {
        runGitAction(label: "Remover worktree", args: ["worktree", "remove", path])
    }

    func openWorktreeTerminal(_ worktree: WorktreeItem) {
        let url = URL(fileURLWithPath: worktree.path)
        let label = worktree.branch.isEmpty ? url.lastPathComponent : worktree.branch
        createTerminalSession(workingDirectory: url, label: label, worktreeID: worktree.id)
    }

    func removeWorktreeAndCloseTerminal(_ worktree: WorktreeItem) {
        closeTerminalSession(forWorktree: worktree.id)
        removeWorktree(worktree.path)
    }

    // MARK: - Terminal Session Management

    func createTerminalSession(workingDirectory: URL, label: String, worktreeID: String? = nil, activate: Bool = true) {
        if let worktreeID, let existing = terminalSessions.first(where: { $0.worktreeID == worktreeID }) {
            if activate { activateSession(existing) }
            return
        }
        let session = TerminalSession(workingDirectory: workingDirectory, label: label, worktreeID: worktreeID)
        let tab = TerminalPaneNode(session: session)
        terminalTabs.append(tab)
        if activate {
            activeTabID = tab.id
            focusedSessionID = session.id
        }
    }

    func closeTerminalSession(_ session: TerminalSession) {
        // Explicitly kill the closed session's process before restructuring the view tree
        session.killCachedProcess()

        // Try to close within a split first
        for tab in terminalTabs {
            if let (parent, isFirst) = tab.findParent(of: session.id) {
                // Collapse: replace split with the surviving child
                if case .split(_, let first, let second) = parent.content {
                    parent.content = isFirst ? second.content : first.content
                }
                if focusedSessionID == session.id {
                    focusedSessionID = tab.allSessions().first?.id
                }
                return
            }
        }
        // Not in a split — remove the entire tab
        terminalTabs.removeAll(where: { tab in
            if case .terminal(let s) = tab.content { return s.id == session.id }
            return false
        })
        if activeTabID != nil && !terminalTabs.contains(where: { $0.id == activeTabID }) {
            activeTabID = terminalTabs.last?.id
        }
        if focusedSessionID == session.id {
            focusedSessionID = terminalSessions.last?.id
        }
    }

    func closeTab(_ tab: TerminalPaneNode) {
        // Kill all terminal processes in this tab before removing
        for session in tab.allSessions() {
            session.killCachedProcess()
        }
        terminalTabs.removeAll(where: { $0.id == tab.id })
        if activeTabID == tab.id {
            activeTabID = terminalTabs.last?.id
            focusedSessionID = terminalTabs.last?.allSessions().first?.id
        }
    }

    func activateTerminalSession(_ session: TerminalSession) {
        activateSession(session)
    }

    private func activateSession(_ session: TerminalSession) {
        // Find which tab contains this session and activate both tab and session
        for tab in terminalTabs {
            if tab.findNode(containing: session.id) != nil {
                activeTabID = tab.id
                focusedSessionID = session.id
                return
            }
        }
    }

    func splitFocusedTerminal(direction: SplitDirection) {
        guard let focusedID = focusedSessionID else { return }
        for tab in terminalTabs {
            if let node = tab.findNode(containing: focusedID) {
                if case .terminal(let session) = node.content {
                    let newSession = TerminalSession(
                        workingDirectory: session.workingDirectory,
                        label: session.label
                    )
                    let firstNode = TerminalPaneNode(session: session)
                    let secondNode = TerminalPaneNode(session: newSession)
                    node.content = .split(direction: direction, first: firstNode, second: secondNode)
                    focusedSessionID = newSession.id
                    return
                }
            }
        }
    }

    func splitFocusedWithSession(_ newSession: TerminalSession, direction: SplitDirection) {
        guard let focusedID = focusedSessionID else {
            let tab = TerminalPaneNode(session: newSession)
            terminalTabs.append(tab)
            activeTabID = tab.id
            focusedSessionID = newSession.id
            return
        }
        for tab in terminalTabs {
            if let node = tab.findNode(containing: focusedID) {
                if case .terminal(let session) = node.content {
                    let firstNode = TerminalPaneNode(session: session)
                    let secondNode = TerminalPaneNode(session: newSession)
                    node.content = .split(direction: direction, first: firstNode, second: secondNode)
                    focusedSessionID = newSession.id
                    return
                }
            }
        }
        let tab = TerminalPaneNode(session: newSession)
        terminalTabs.append(tab)
        activeTabID = tab.id
        focusedSessionID = newSession.id
    }

    func quickCreateWorktree() {
        guard let repositoryURL else { return }
        let repoName = repositoryURL.lastPathComponent
        let parentDir = repositoryURL.deletingLastPathComponent()
        var n = 1
        while FileManager.default.fileExists(atPath: parentDir.appendingPathComponent("\(repoName)-wt-\(n)").path) {
            n += 1
        }
        let wtPath = parentDir.appendingPathComponent("\(repoName)-wt-\(n)").path
        let branchName = "wt-\(n)"

        actionTask?.cancel()
        isBusy = true
        actionTask = Task {
            do {
                let _ = try await worker.runAction(args: ["worktree", "add", "-b", branchName, wtPath], in: repositoryURL)
                try Task.checkCancellation()
                clearError()
                let wtSession = TerminalSession(workingDirectory: URL(fileURLWithPath: wtPath), label: branchName, worktreeID: wtPath)
                splitFocusedWithSession(wtSession, direction: .vertical)
                statusMessage = "Worktree criado: \(repoName)-wt-\(n)"
                refreshRepository(setBusy: true)
            } catch is CancellationError { return }
            catch { isBusy = false; handleError(error) }
        }
    }

    func closeFocusedTerminalPane() {
        guard let focusedID = focusedSessionID,
              let session = terminalSessions.first(where: { $0.id == focusedID }) else { return }
        closeTerminalSession(session)
    }

    private func closeTerminalSession(forWorktree worktreeID: String) {
        if let session = terminalSessions.first(where: { $0.worktreeID == worktreeID }) {
            closeTerminalSession(session)
        }
    }

    func createDefaultTerminalSession(repositoryURL: URL?, branchName: String) {
        let workingDirectory = repositoryURL ?? URL(fileURLWithPath: NSHomeDirectory())

        // If we already have a session for THIS directory, just activate it
        if let existing = terminalSessions.first(where: { $0.workingDirectory.path == workingDirectory.path }) {
            activateSession(existing)
            return
        }

        // Otherwise create a new one
        createTerminalSession(workingDirectory: workingDirectory, label: branchName)
    }

    func pruneWorktrees() {
        runGitAction(label: "Worktree prune", args: ["worktree", "prune"])
    }

    func pruneMergedBranches() {
        actionTask?.cancel()
        isBusy = true
        
        let url = repositoryURL
        actionTask = Task {
            do {
                guard let url else { return }
                // 1. Get branches merged into main
                let result = try await worker.runAction(args: ["branch", "--merged", "main"], in: url)
                let branchesToDelete = result.split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && !$0.hasPrefix("*") && $0 != "main" && $0 != "master" }
                
                if branchesToDelete.isEmpty {
                    statusMessage = L10n("Nenhuma branch mesclada encontrada.")
                    isBusy = false
                    return
                }
                
                // 2. Delete them
                let _ = try await worker.runAction(args: ["branch", "-d"] + branchesToDelete, in: url)
                clearError()
                let list = branchesToDelete.joined(separator: ", ")
                statusMessage = L10n("Branches removidas: %@", list)
                refreshRepository(setBusy: true)
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    func initRepository() {
        runGitAction(label: "Git Init", args: ["init"])
    }

    func addRemote() {
        let name = remoteNameInput.clean
        let url = remoteURLInput.clean
        guard !name.isEmpty, !url.isEmpty else { return }
        runGitAction(label: "Add Remote", args: ["remote", "add", name, url])
    }

    func removeRemote(named name: String) {
        runGitAction(label: "Remove Remote", args: ["remote", "remove", name])
    }

    func testRemote(named name: String) {
        runGitAction(label: "Test Remote", args: ["ls-remote", "--exit-code", name])
    }

    func commit(message: String) {
        let msg = message.clean
        guard !msg.isEmpty else { return }
        
        actionTask?.cancel()
        isBusy = true
        
        let url = repositoryURL
        let shouldAmend = amendLastCommit
        
        actionTask = Task {
            do {
                guard let url else { return }
                
                // 1. Always stage everything first for a guaranteed "Quick Commit"
                // This handles both modified and untracked files.
                let _ = try await worker.runAction(args: ["add", "-A"], in: url)
                
                // 2. Prepare commit arguments
                var commitArgs = ["commit", "-m", msg]
                if shouldAmend {
                    commitArgs.append("--amend")
                }
                
                // 3. Execute commit
                let _ = try await worker.runAction(args: commitArgs, in: url)
                
                clearError()
                statusMessage = shouldAmend ? L10n("Commit corrigido com sucesso.") : L10n("Commit realizado com sucesso.")
                commitMessageInput = ""
                amendLastCommit = false
                refreshRepository(setBusy: true)
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    func stageFile(_ path: String) {
        runGitAction(label: "Stage", args: ["add", path])
    }

    func unstageFile(_ path: String) {
        runGitAction(label: "Unstage", args: ["reset", "HEAD", "--", path])
    }

    func stageAllFiles() {
        runGitAction(label: "Stage All", args: ["add", "-A"])
    }

    func unstageAllFiles() {
        runGitAction(label: "Unstage All", args: ["reset", "HEAD", "--", "."])
    }

    func addToGitIgnore(path: String) {
        guard let url = repositoryURL else { return }
        let gitIgnoreURL = url.appendingPathComponent(".gitignore")
        
        actionTask?.cancel()
        isBusy = true
        
        actionTask = Task {
            do {
                var content = ""
                if FileManager.default.fileExists(atPath: gitIgnoreURL.path) {
                    content = try String(contentsOf: gitIgnoreURL, encoding: .utf8)
                }
                
                if !content.contains(path) {
                    if !content.isEmpty && !content.hasSuffix("\n") {
                        content += "\n"
                    }
                    content += "\(path)\n"
                    try content.write(to: gitIgnoreURL, atomically: true, encoding: .utf8)
                }
                
                // After adding to gitignore, we should unstage it if it was staged
                let _ = try await worker.runAction(args: ["rm", "--cached", path], in: url)
                
                clearError()
                statusMessage = L10n("Adicionado ao .gitignore: %@", path)
                refreshRepository(setBusy: true)
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    func renameRemote(oldName: String, newName: String) {
        runGitAction(label: "Rename Remote", args: ["remote", "rename", oldName, newName])
    }

    func abortMerge() { runGitAction(label: "Abort Merge", args: ["merge", "--abort"]) }
    func abortRebase() { runGitAction(label: "Abort Rebase", args: ["rebase", "--abort"]) }
    func abortCherryPick() { runGitAction(label: "Abort Cherry-pick", args: ["cherry-pick", "--abort"]) }

    // MARK: - Conflict Resolution

    func loadConflictedFiles() {
        guard let repositoryURL else { return }
        conflictTask?.cancel()
        conflictTask = Task {
            do {
                let files = try await worker.listConflictedFiles(in: repositoryURL)
                try Task.checkCancellation()
                conflictedFiles = files
                if let first = files.first(where: { !$0.isResolved }) {
                    selectConflictFile(first.path)
                }
            } catch is CancellationError {
                return
            } catch {
                handleError(error)
            }
        }
    }

    func selectConflictFile(_ path: String) {
        guard let repositoryURL else { return }
        selectedConflictFile = path
        conflictTask?.cancel()
        conflictTask = Task {
            do {
                let content = try await worker.readConflictFileContent(path: path, in: repositoryURL)
                try Task.checkCancellation()
                conflictBlocks = Self.parseConflictBlocks(content)
            } catch is CancellationError {
                return
            } catch {
                handleError(error)
            }
        }
    }

    func resolveRegion(_ regionID: UUID, choice: ConflictChoice) {
        for i in conflictBlocks.indices {
            if case .conflict(var region) = conflictBlocks[i], region.id == regionID {
                region.choice = choice
                conflictBlocks[i] = .conflict(region)
                break
            }
        }
    }

    func saveAndMarkResolved(_ path: String) {
        guard let repositoryURL else { return }
        let merged = buildMergedContent()
        conflictTask?.cancel()
        conflictTask = Task {
            do {
                try await worker.writeResolvedFile(path: path, content: merged, in: repositoryURL)
                try await worker.markFileResolved(path: path, in: repositoryURL)
                try Task.checkCancellation()
                if let idx = conflictedFiles.firstIndex(where: { $0.path == path }) {
                    conflictedFiles[idx].isResolved = true
                }
                statusMessage = "\(path) " + L10n("Marcar como Resolvido")
                // Select next unresolved file
                if let next = conflictedFiles.first(where: { !$0.isResolved }) {
                    selectConflictFile(next.path)
                } else {
                    selectedConflictFile = nil
                    conflictBlocks = []
                }
            } catch is CancellationError {
                return
            } catch {
                handleError(error)
            }
        }
    }

    func continueAfterResolution() {
        guard let repositoryURL else { return }
        isBusy = true
        conflictTask?.cancel()
        conflictTask = Task {
            do {
                let output = try await worker.continueOperation(in: repositoryURL)
                try Task.checkCancellation()
                isConflictViewVisible = false
                statusMessage = output.isEmpty ? L10n("Todos os conflitos resolvidos!") : String(output.prefix(240))
                refreshRepository(setBusy: true)
            } catch is CancellationError {
                return
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    var allConflictsResolved: Bool {
        !conflictedFiles.isEmpty && conflictedFiles.allSatisfy(\.isResolved)
    }

    var unresolvedConflictCount: Int {
        conflictedFiles.filter { !$0.isResolved }.count
    }

    var currentFileAllRegionsChosen: Bool {
        conflictBlocks.allSatisfy { block in
            if case .conflict(let region) = block { return region.choice != .undecided }
            return true
        }
    }

    var activeOperationLabel: String {
        if isMerging { return "Merge" }
        if isRebasing { return "Rebase" }
        if isCherryPicking { return "Cherry-pick" }
        return ""
    }

    private func buildMergedContent() -> String {
        var lines: [String] = []
        for block in conflictBlocks {
            switch block {
            case .context(let contextLines):
                lines.append(contentsOf: contextLines)
            case .conflict(let region):
                switch region.choice {
                case .undecided:
                    // Keep original markers if undecided
                    lines.append("<<<<<<< \(region.oursLabel)")
                    lines.append(contentsOf: region.oursLines)
                    lines.append("=======")
                    lines.append(contentsOf: region.theirsLines)
                    lines.append(">>>>>>> \(region.theirsLabel)")
                case .ours:
                    lines.append(contentsOf: region.oursLines)
                case .theirs:
                    lines.append(contentsOf: region.theirsLines)
                case .both:
                    lines.append(contentsOf: region.oursLines)
                    lines.append(contentsOf: region.theirsLines)
                case .bothReverse:
                    lines.append(contentsOf: region.theirsLines)
                    lines.append(contentsOf: region.oursLines)
                case .custom(let text):
                    lines.append(contentsOf: text.components(separatedBy: "\n"))
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    static func parseConflictBlocks(_ content: String) -> [ConflictBlock] {
        let lines = content.components(separatedBy: "\n")
        var blocks: [ConflictBlock] = []
        var contextBuffer: [String] = []
        var oursBuffer: [String] = []
        var theirsBuffer: [String] = []
        var oursLabel = ""
        var theirsLabel = ""
        var inOurs = false
        var inTheirs = false

        for line in lines {
            if line.hasPrefix("<<<<<<< ") {
                if !contextBuffer.isEmpty {
                    blocks.append(.context(contextBuffer))
                    contextBuffer = []
                }
                oursLabel = String(line.dropFirst(8))
                oursBuffer = []
                inOurs = true
                inTheirs = false
            } else if line == "=======" && inOurs {
                inOurs = false
                inTheirs = true
                theirsBuffer = []
            } else if line.hasPrefix(">>>>>>> ") && inTheirs {
                theirsLabel = String(line.dropFirst(8))
                let region = ConflictRegion(
                    oursLines: oursBuffer,
                    theirsLines: theirsBuffer,
                    oursLabel: oursLabel,
                    theirsLabel: theirsLabel
                )
                blocks.append(.conflict(region))
                inTheirs = false
                oursBuffer = []
                theirsBuffer = []
            } else if inOurs {
                oursBuffer.append(line)
            } else if inTheirs {
                theirsBuffer.append(line)
            } else {
                contextBuffer.append(line)
            }
        }
        if !contextBuffer.isEmpty {
            blocks.append(.context(contextBuffer))
        }
        return blocks
    }

    func createArchive(reference: String, outputPath: String) {
        let ref = reference.clean
        let path = outputPath.clean
        guard !ref.isEmpty, !path.isEmpty else { return }
        runGitAction(label: "Create archive", args: ["archive", "--format=zip", "--output", path, ref])
    }

    func deleteLocalBranch(_ branch: String, force: Bool) {
        let name = branch.clean
        guard !name.isEmpty else { return }
        runGitAction(
            label: "Delete local branch",
            args: ["branch", force ? "-D" : "-d", name]
        )
    }

    func branchInfo(named name: String) -> BranchInfo? {
        branchInfos.first(where: { $0.name == name })
    }

    func localBranchExists(named name: String) -> Bool {
        branchInfos.contains(where: { !$0.isRemote && $0.name == name })
    }

    func isRemoteRefName(_ value: String) -> Bool {
        branchInfos.contains(where: { $0.isRemote && $0.name == value })
    }

    private func resolveStashReference(_ input: String) async -> String? {
        let value = input.clean
        guard !value.isEmpty else { return nil }
        
        // 1. If it's already a stash@{n} format, try to extract just that part
        if value.hasPrefix("stash@{") || value.contains("stash@{") {
            if let range = value.range(of: "stash@{[0-9]+}", options: .regularExpression) {
                return String(value[range])
            }
        }
        
        // 2. If it's a hash, we need to find which stash@{n} corresponds to it
        let isHex = value.range(of: "^[0-9a-fA-F]{7,40}$", options: .regularExpression) != nil
        if isHex {
            guard let url = repositoryURL else { return value }
            // Run git stash list with hashes to find the match
            do {
                let output = try await worker.runAction(args: ["stash", "list", "--format=%H %gD"], in: url)
                for line in output.split(separator: "\n") {
                    let parts = line.split(separator: " ")
                    if parts.count >= 2 {
                        let hash = String(parts[0])
                        let stashRef = String(parts[1])
                        if hash.hasPrefix(value) || value.hasPrefix(hash) {
                            return stashRef // Found stash@{n}
                        }
                    }
                }
            } catch {
                logger.log(.warn, "Failed to resolve stash ref: \(error.localizedDescription)", context: value, source: #function)
                return value // Fallback to hash if it fails
            }
        }
        
        return value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? value
    }

    private func refreshCommitsOnly() {
        guard let repositoryURL else {
            lastError = GitClientError.repositoryNotSelected.localizedDescription
            hasMoreCommits = false
            return
        }

        refreshTask?.cancel()
        let requestID = UUID()
        refreshRequestID = requestID
        isBusy = true

        let focusedBranchSnapshot = focusedBranch
        let selectedCommitSnapshot = selectedCommitID
        let commitLimitSnapshot = commitLimit

        refreshTask = Task {
            do {
                let payload = try await worker.loadCommits(
                    in: repositoryURL,
                    reference: focusedBranchSnapshot,
                    selectedCommitID: selectedCommitSnapshot,
                    limit: commitLimitSnapshot
                )
                try Task.checkCancellation()
                guard refreshRequestID == requestID else { return }

                clearError()
                commits = payload.commits
                hasMoreCommits = payload.hasMore
                selectedCommitID = payload.selectedCommitID
                if let focusedBranchSnapshot {
                    statusMessage = L10n("Filtro de branch ativo: %@ · %@ commits", focusedBranchSnapshot, "\(payload.commits.count)")
                } else {
                    statusMessage = L10n("Visualizando todas as branches · %@ commits", "\(payload.commits.count)")
                }
                isBusy = false
                loadCommitDetails(for: payload.selectedCommitID)
            } catch is CancellationError {
                return
            } catch {
                guard refreshRequestID == requestID else { return }
                isBusy = false
                handleError(error)
            }
        }
    }

    private func refreshRepository(setBusy: Bool) {
        guard let repositoryURL else {
            lastError = GitClientError.repositoryNotSelected.localizedDescription
            hasMoreCommits = false
            return
        }

        refreshTask?.cancel()
        let requestID = UUID()
        refreshRequestID = requestID
        if setBusy {
            isBusy = true
        }

        let focusedBranchSnapshot = focusedBranch
        let selectedCommitSnapshot = selectedCommitID
        let selectedStashSnapshot = selectedStash
        let inferOrigins = inferBranchOrigins
        let commitLimitSnapshot = commitLimit

        refreshTask = Task {
            do {
                let payload = try await worker.loadRepository(
                    in: repositoryURL,
                    focusedBranch: focusedBranchSnapshot,
                    selectedCommitID: selectedCommitSnapshot,
                    selectedStash: selectedStashSnapshot,
                    inferOrigins: inferOrigins,
                    limit: commitLimitSnapshot
                )
                try Task.checkCancellation()
                guard refreshRequestID == requestID else { return }

                clearError()
                currentBranch = payload.currentBranch
                headShortHash = payload.headShortHash
                branchInfos = payload.branchInfos
                branches = payload.branches
                focusedBranch = payload.focusedBranch
                branchTree = payload.branchTree
                tags = payload.tags
                stashes = payload.stashes
                selectedStash = payload.selectedStash
                worktrees = payload.worktrees
                remotes = payload.remotes
                commits = payload.commits
                hasMoreCommits = payload.hasMoreCommits
                selectedCommitID = payload.selectedCommitID
                hasConflicts = payload.hasConflicts
                isMerging = payload.isMerging
                isRebasing = payload.isRebasing
                isCherryPicking = payload.isCherryPicking
                isGitRepository = payload.isGitRepository
                uncommittedChanges = payload.uncommittedChanges
                uncommittedCount = payload.uncommittedCount
                statusMessage = L10n("Repositorio carregado: %@ · %@ commits", repositoryURL.lastPathComponent, "\(payload.commits.count)")
                if setBusy {
                    isBusy = false
                }
                loadCommitDetails(for: payload.selectedCommitID)
            } catch is CancellationError {
                return
            } catch {
                guard refreshRequestID == requestID else { return }
                if setBusy {
                    isBusy = false
                }
                handleError(error)
            }
        }
    }

    private func runGitAction(label: String, args: [String]) {
        guard let repositoryURL else {
            lastError = GitClientError.repositoryNotSelected.localizedDescription
            return
        }

        actionTask?.cancel()
        isBusy = true

        let command = "git " + args.joined(separator: " ")
        logger.log(.git, command, context: label)

        actionTask = Task {
            do {
                let output = try await worker.runAction(args: args, in: repositoryURL)
                try Task.checkCancellation()

                clearError()
                if output.isEmpty {
                    statusMessage = "\(label) executado com sucesso."
                } else {
                    statusMessage = "\(label): \(output.prefix(240))"
                }
                logger.log(.git, "\(label) OK", context: command)
                refreshRepository(setBusy: true)
            } catch is CancellationError {
                return
            } catch {
                isBusy = false
                logger.log(.error, error.localizedDescription, context: command)
                handleError(error)
            }
        }
    }

    private func loadCommitDetails(for commitID: String?) {
        guard let repositoryURL else {
            commitDetails = "Selecione um repositorio Git."
            return
        }

        guard let commitID else {
            commitDetails = "Selecione um commit para ver os detalhes."
            return
        }

        detailsTask?.cancel()
        let requestID = UUID()
        detailsRequestID = requestID
        commitDetails = "Carregando detalhes do commit..."

        detailsTask = Task {
            do {
                let details = try await worker.loadCommitDetails(in: repositoryURL, commitID: commitID)
                try Task.checkCancellation()
                guard detailsRequestID == requestID else { return }
                commitDetails = details
            } catch is CancellationError {
                return
            } catch {
                guard detailsRequestID == requestID else { return }
                logger.log(.warn, "Failed to load commit details: \(error.localizedDescription)", context: commitID, source: #function)
                commitDetails = error.localizedDescription
            }
        }
    }

    private func loadDiff(for file: String) {
        guard let url = repositoryURL else { return }

        Task {
            do {
                // Get diff including staged changes
                let diff = try await worker.runAction(args: ["diff", "HEAD", "--", file], in: url)
                if diff.isEmpty {
                    currentFileDiff = L10n("Nenhuma mudanca detectada (ou arquivo novo nao rastreado).")
                    currentFileDiffHunks = []
                } else {
                    currentFileDiff = diff
                    currentFileDiffHunks = Self.parseDiffHunks(diff)
                }
                selectedHunkLines = []
            } catch {
                logger.log(.warn, "Failed to load diff: \(error.localizedDescription)", context: file, source: #function)
                currentFileDiff = "Erro ao carregar diff: \(error.localizedDescription)"
                currentFileDiffHunks = []
            }
        }
    }

    // MARK: - Terminal Paste

    func sendTextToActiveTerminal(_ text: String) {
        guard let activeID = activeTerminalID,
              let callback = terminalSendCallbacks[activeID],
              let data = text.data(using: .utf8) else { return }
        callback(data)
    }

    func registerTerminalSendCallback(sessionID: UUID, callback: @escaping (Data) -> Void) {
        terminalSendCallbacks[sessionID] = callback
    }

    func unregisterTerminalSendCallback(sessionID: UUID) {
        terminalSendCallbacks.removeValue(forKey: sessionID)
    }

    // MARK: - Diff Parsing

    static func parseDiffHunks(_ rawDiff: String) -> [DiffHunk] {
        let lines = rawDiff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var hunks: [DiffHunk] = []
        var i = 0

        // Skip file header lines (diff --git, index, ---, +++)
        while i < lines.count && !lines[i].hasPrefix("@@") {
            i += 1
        }

        while i < lines.count {
            let line = lines[i]
            guard line.hasPrefix("@@") else { i += 1; continue }

            // Parse hunk header: @@ -oldStart,oldCount +newStart,newCount @@
            let header = line
            var oldStart = 0, oldCount = 0, newStart = 0, newCount = 0
            if let rangeMatch = line.range(of: "@@ -(\\d+)(?:,(\\d+))? \\+(\\d+)(?:,(\\d+))? @@",
                                           options: .regularExpression) {
                let headerStr = String(line[rangeMatch])
                let nums = headerStr.matches(of: /(\d+)/)
                if nums.count >= 3 {
                    oldStart = Int(nums[0].output.1) ?? 0
                    if nums.count == 4 {
                        oldCount = Int(nums[1].output.1) ?? 0
                        newStart = Int(nums[2].output.1) ?? 0
                        newCount = Int(nums[3].output.1) ?? 0
                    } else {
                        oldCount = 0
                        newStart = Int(nums[1].output.1) ?? 0
                        newCount = Int(nums[2].output.1) ?? 0
                    }
                }
            }

            i += 1
            var diffLines: [DiffLine] = []
            var currentOld = oldStart
            var currentNew = newStart

            while i < lines.count && !lines[i].hasPrefix("@@") {
                let diffLineText = lines[i]
                if diffLineText.hasPrefix("+") {
                    diffLines.append(DiffLine(type: .addition, content: String(diffLineText.dropFirst()),
                                              oldLineNumber: nil, newLineNumber: currentNew))
                    currentNew += 1
                } else if diffLineText.hasPrefix("-") {
                    diffLines.append(DiffLine(type: .deletion, content: String(diffLineText.dropFirst()),
                                              oldLineNumber: currentOld, newLineNumber: nil))
                    currentOld += 1
                } else if diffLineText.hasPrefix("\\") {
                    // "\ No newline at end of file" — skip
                    i += 1
                    continue
                } else {
                    // Context line (starts with space or is empty)
                    let content = diffLineText.isEmpty ? "" : String(diffLineText.dropFirst())
                    diffLines.append(DiffLine(type: .context, content: content,
                                              oldLineNumber: currentOld, newLineNumber: currentNew))
                    currentOld += 1
                    currentNew += 1
                }
                i += 1
            }

            hunks.append(DiffHunk(header: header, oldStart: oldStart, oldCount: oldCount,
                                  newStart: newStart, newCount: newCount, lines: diffLines))
        }

        return hunks
    }

    // MARK: - Hunk & Line Staging

    func stageHunk(_ hunk: DiffHunk, file: String) {
        guard let url = repositoryURL else { return }
        let patch = buildPatch(file: file, hunks: [hunk])

        actionTask?.cancel()
        isBusy = true
        actionTask = Task {
            do {
                let _ = try await worker.runActionWithStdin(
                    args: ["apply", "--cached", "--unidiff-zero"],
                    stdin: patch,
                    in: url
                )
                clearError()
                statusMessage = L10n("Hunk staged com sucesso.")
                refreshRepository(setBusy: true)
                if let file = selectedChangeFile { loadDiff(for: file) }
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    func unstageHunk(_ hunk: DiffHunk, file: String) {
        guard let url = repositoryURL else { return }
        let patch = buildPatch(file: file, hunks: [hunk])

        actionTask?.cancel()
        isBusy = true
        actionTask = Task {
            do {
                let _ = try await worker.runActionWithStdin(
                    args: ["apply", "--cached", "--reverse", "--unidiff-zero"],
                    stdin: patch,
                    in: url
                )
                clearError()
                statusMessage = L10n("Hunk unstaged com sucesso.")
                refreshRepository(setBusy: true)
                if let file = selectedChangeFile { loadDiff(for: file) }
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    func stageSelectedLines(from hunk: DiffHunk, selectedLineIDs: Set<UUID>, file: String) {
        guard let url = repositoryURL else { return }
        let patch = buildPartialPatch(file: file, hunk: hunk, selectedLineIDs: selectedLineIDs)
        guard !patch.isEmpty else { return }

        actionTask?.cancel()
        isBusy = true
        actionTask = Task {
            do {
                let _ = try await worker.runActionWithStdin(
                    args: ["apply", "--cached", "--unidiff-zero"],
                    stdin: patch,
                    in: url
                )
                clearError()
                statusMessage = L10n("Linhas staged com sucesso.")
                refreshRepository(setBusy: true)
                if let file = selectedChangeFile { loadDiff(for: file) }
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    private func buildPatch(file: String, hunks: [DiffHunk]) -> String {
        var patch = "--- a/\(file)\n+++ b/\(file)\n"
        for hunk in hunks {
            patch += hunk.header + "\n"
            for line in hunk.lines {
                switch line.type {
                case .context: patch += " \(line.content)\n"
                case .addition: patch += "+\(line.content)\n"
                case .deletion: patch += "-\(line.content)\n"
                }
            }
        }
        return patch
    }

    private func buildPartialPatch(file: String, hunk: DiffHunk, selectedLineIDs: Set<UUID>) -> String {
        // Build a hunk with only the selected changed lines; unselected changes become context
        var newLines: [DiffLine] = []
        var oldLineCount = 0
        var newLineCount = 0

        for line in hunk.lines {
            let isSelected = selectedLineIDs.contains(line.id)
            switch line.type {
            case .context:
                newLines.append(line)
                oldLineCount += 1
                newLineCount += 1
            case .addition:
                if isSelected {
                    newLines.append(line)
                    newLineCount += 1
                }
                // If not selected, skip the addition entirely
            case .deletion:
                if isSelected {
                    newLines.append(line)
                    oldLineCount += 1
                } else {
                    // Unselected deletion becomes context
                    newLines.append(DiffLine(type: .context, content: line.content,
                                             oldLineNumber: line.oldLineNumber, newLineNumber: nil))
                    oldLineCount += 1
                    newLineCount += 1
                }
            }
        }

        guard newLines.contains(where: { $0.type != .context }) else { return "" }

        let header = "@@ -\(hunk.oldStart),\(oldLineCount) +\(hunk.newStart),\(newLineCount) @@"
        var patch = "--- a/\(file)\n+++ b/\(file)\n\(header)\n"
        for line in newLines {
            switch line.type {
            case .context: patch += " \(line.content)\n"
            case .addition: patch += "+\(line.content)\n"
            case .deletion: patch += "-\(line.content)\n"
            }
        }
        return patch
    }

    // MARK: - Commit Diff for File

    func loadDiffForCommitFile(commitID: String, file: String) {
        guard let url = repositoryURL else { return }
        Task {
            do {
                let diff = try await worker.runAction(
                    args: ["diff", "\(commitID)~1", commitID, "--", file],
                    in: url
                )
                currentFileDiff = diff.isEmpty ? L10n("Nenhuma mudanca.") : diff
                currentFileDiffHunks = Self.parseDiffHunks(diff)
            } catch {
                logger.log(.warn, "Failed to load commit file diff: \(error.localizedDescription)", context: "\(commitID):\(file)", source: #function)
                currentFileDiff = "Erro: \(error.localizedDescription)"
                currentFileDiffHunks = []
            }
        }
    }

    // MARK: - Git Blame

    func loadBlame(for file: FileItem) {
        guard let url = repositoryURL else { return }
        let filePath: String
        if let repoURL = repositoryURL {
            filePath = file.url.path.replacingOccurrences(of: repoURL.path + "/", with: "")
        } else {
            filePath = file.name
        }

        blameTask?.cancel()
        blameEntries = []

        blameTask = Task {
            do {
                let output = try await worker.runAction(
                    args: ["blame", "--porcelain", filePath],
                    in: url
                )
                let entries = Self.parseBlameOutput(output)
                blameEntries = entries
            } catch {
                logger.log(.warn, "Failed to load blame: \(error.localizedDescription)", context: filePath, source: #function)
                blameEntries = []
                statusMessage = "Blame: \(error.localizedDescription)"
            }
        }
    }

    func toggleBlame() {
        isBlameVisible.toggle()
        if isBlameVisible, let file = selectedCodeFile {
            loadBlame(for: file)
        } else {
            blameEntries = []
        }
    }

    static func parseBlameOutput(_ raw: String) -> [BlameEntry] {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var entries: [BlameEntry] = []
        var i = 0
        var authorMap: [String: String] = [:]
        var dateMap: [String: Date] = [:]

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        while i < lines.count {
            let line = lines[i]
            // Header line: <hash> <orig-line> <final-line> [<num-lines>]
            let parts = line.split(separator: " ")
            guard parts.count >= 3,
                  let hash = parts.first, hash.count >= 7,
                  hash.allSatisfy({ $0.isHexDigit }),
                  let lineNum = Int(parts[2]) else {
                i += 1
                continue
            }

            let commitHash = String(hash)
            i += 1

            // Read metadata lines until we hit the tab-prefixed content line
            var author = authorMap[commitHash] ?? ""
            var date = dateMap[commitHash] ?? Date.distantPast

            while i < lines.count && !lines[i].hasPrefix("\t") {
                let metaLine = lines[i]
                if metaLine.hasPrefix("author ") {
                    author = String(metaLine.dropFirst(7))
                    authorMap[commitHash] = author
                } else if metaLine.hasPrefix("author-time ") {
                    if let ts = TimeInterval(metaLine.dropFirst(12)) {
                        date = Date(timeIntervalSince1970: ts)
                        dateMap[commitHash] = date
                    }
                }
                i += 1
            }

            // Content line (starts with tab)
            var content = ""
            if i < lines.count && lines[i].hasPrefix("\t") {
                content = String(lines[i].dropFirst(1))
            }
            i += 1

            entries.append(BlameEntry(
                commitHash: commitHash,
                shortHash: String(commitHash.prefix(8)),
                author: author,
                date: date,
                lineNumber: lineNum,
                content: content
            ))
        }

        return entries
    }

    // MARK: - Reflog

    func loadReflog() {
        guard let url = repositoryURL else { return }

        reflogTask?.cancel()
        reflogEntries = []

        reflogTask = Task {
            do {
                let output = try await worker.runAction(
                    args: ["reflog", "--format=%H|%h|%gD|%gs|%ci|%cr", "-n", "50"],
                    in: url
                )
                let entries = Self.parseReflogOutput(output)
                reflogEntries = entries
            } catch {
                logger.log(.warn, "Failed to load reflog: \(error.localizedDescription)", source: #function)
                reflogEntries = []
            }
        }
    }

    func undoLastAction() {
        guard !reflogEntries.isEmpty else { return }
        // Find the previous state (reflog entry at index 1)
        guard reflogEntries.count > 1 else { return }
        let target = reflogEntries[1]
        runGitAction(label: "Undo", args: ["reset", "--soft", target.hash])
    }

    static func parseReflogOutput(_ raw: String) -> [ReflogEntry] {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"

        return lines.compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 5).map(String.init)
            guard parts.count >= 6 else { return nil }

            let hash = parts[0]
            let shortHash = parts[1]
            let refName = parts[2]
            let message = parts[3]
            let dateStr = parts[4]
            let relDate = parts[5]

            // Parse action type from message (e.g. "commit: ..." -> "commit")
            let action = message.split(separator: ":", maxSplits: 1).first.map(String.init) ?? message

            let date = dateFormatter.date(from: dateStr) ?? Date.distantPast

            return ReflogEntry(
                hash: hash,
                shortHash: shortHash,
                refName: refName,
                action: action,
                message: message,
                date: date,
                relativeDate: relDate
            )
        }
    }

    // MARK: - Interactive Rebase

    func prepareInteractiveRebase(from baseRef: String) {
        guard let url = repositoryURL else { return }
        rebaseBaseRef = baseRef

        Task {
            do {
                let output = try await worker.runAction(
                    args: ["log", "--oneline", "--reverse", "\(baseRef)..HEAD"],
                    in: url
                )
                let items = output.split(separator: "\n", omittingEmptySubsequences: true).map { line -> RebaseItem in
                    let parts = line.split(separator: " ", maxSplits: 1)
                    let hash = parts.count > 0 ? String(parts[0]) : ""
                    let subject = parts.count > 1 ? String(parts[1]) : ""
                    return RebaseItem(hash: hash, shortHash: String(hash.prefix(8)), subject: subject)
                }
                rebaseItems = items
                isRebaseSheetVisible = true
            } catch {
                handleError(error)
            }
        }
    }

    func executeInteractiveRebase() {
        guard let url = repositoryURL, !rebaseItems.isEmpty else { return }

        // Build the rebase todo list
        let todoList = rebaseItems.map { item in
            "\(item.action.rawValue) \(item.hash) \(item.subject)"
        }.joined(separator: "\n")

        actionTask?.cancel()
        isBusy = true
        isRebaseSheetVisible = false

        actionTask = Task {
            do {
                // Use GIT_SEQUENCE_EDITOR to pass the todo list
                // We write the todo to a temp file and use a script that replaces the editor
                let tempDir = FileManager.default.temporaryDirectory
                let todoFile = tempDir.appendingPathComponent("zion-rebase-todo-\(UUID().uuidString)")
                try todoList.write(to: todoFile, atomically: true, encoding: .utf8)

                let scriptContent = "#!/bin/sh\ncp \"\(todoFile.path)\" \"$1\""
                let scriptFile = tempDir.appendingPathComponent("zion-rebase-editor-\(UUID().uuidString).sh")
                try scriptContent.write(to: scriptFile, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptFile.path)

                // Run rebase with our custom sequence editor
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["git", "rebase", "-i", rebaseBaseRef]
                process.currentDirectoryURL = url
                var env = ProcessInfo.processInfo.environment
                env["GIT_SEQUENCE_EDITOR"] = scriptFile.path
                env["LC_ALL"] = "C"
                env["LANG"] = "C"
                process.environment = env

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                try process.run()
                process.waitUntilExit()

                // Cleanup temp files
                try? FileManager.default.removeItem(at: todoFile)
                try? FileManager.default.removeItem(at: scriptFile)

                let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

                if process.terminationStatus != 0 {
                    handleError(GitClientError.commandFailed(
                        command: "git rebase -i \(rebaseBaseRef)",
                        message: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                    isBusy = false
                } else {
                    clearError()
                    statusMessage = L10n("Rebase interativo concluido com sucesso.")
                    refreshRepository(setBusy: true)
                }
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    // MARK: - GitHub PR Integration

    func loadPullRequests() {
        guard let remote = detectGitHubRemote() else { return }

        prTask?.cancel()
        prTask = Task {
            let prs = await githubClient.fetchPullRequests(remote: remote)
            pullRequests = prs
        }
    }

    func prForBranch(_ branch: String) -> GitHubPRInfo? {
        pullRequests.first { $0.headBranch == branch }
    }

    var hasGitHubRemote: Bool {
        detectGitHubRemote() != nil
    }

    private func detectGitHubRemote() -> GitHubRemote? {
        for remote in remotes {
            if let gh = GitHubClient.parseRemote(remote.url) {
                return gh
            }
        }
        return nil
    }

    // MARK: - Submodules

    func loadSubmodules() {
        guard let url = repositoryURL else { return }

        Task {
            do {
                let output = try await worker.runAction(args: ["submodule", "status"], in: url)
                submodules = Self.parseSubmoduleStatus(output, repoURL: url)
            } catch {
                logger.log(.warn, "Failed to load submodules: \(error.localizedDescription)", source: #function)
                submodules = []
            }
        }
    }

    func submoduleInit() {
        runGitAction(label: "Submodule init", args: ["submodule", "init"])
    }

    func submoduleUpdate(recursive: Bool) {
        var args = ["submodule", "update", "--init"]
        if recursive { args.append("--recursive") }
        runGitAction(label: "Submodule update", args: args)
    }

    func submoduleSync() {
        runGitAction(label: "Submodule sync", args: ["submodule", "sync"])
    }

    static func parseSubmoduleStatus(_ raw: String, repoURL: URL) -> [SubmoduleInfo] {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        return lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }

            let statusChar = trimmed.first
            let rest = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            let parts = rest.split(separator: " ", maxSplits: 1)
            guard parts.count >= 1 else { return nil }

            let hash = String(parts[0])
            let path = parts.count > 1 ? String(parts[1]).split(separator: " ").first.map(String.init) ?? "" : ""

            let status: SubmoduleInfo.SubmoduleStatus
            switch statusChar {
            case "-": status = .uninitialized
            case "+": status = .modified
            default: status = .upToDate
            }

            return SubmoduleInfo(name: URL(fileURLWithPath: path).lastPathComponent,
                               path: path, url: "", hash: hash, status: status)
        }
    }

    // MARK: - Auth Error Detection

    func detectAuthError(from errorMessage: String) -> String? {
        let patterns = [
            "Permission denied",
            "Could not read from remote",
            "Authentication failed",
            "fatal: repository.*not found",
            "ERROR: Repository not found",
            "Host key verification failed"
        ]
        for pattern in patterns {
            if errorMessage.range(of: pattern, options: .regularExpression) != nil {
                return errorMessage
            }
        }
        return nil
    }

    // MARK: - AI Commit Message

    func suggestCommitMessage() {
        guard let url = repositoryURL else { return }

        aiTask?.cancel()
        aiTask = Task {
            isGeneratingAIMessage = true
            defer { isGeneratingAIMessage = false }

            do {
                aiQuotaExceeded = false
                let diffStatOutput = try await worker.runAction(args: ["diff", "--cached", "--stat"], in: url)
                var diffStat = diffStatOutput
                let status = try await worker.runAction(args: ["status", "--porcelain"], in: url)

                logger.log(.ai, "AI Configured: \(isAIConfigured), Provider: \(aiProvider.rawValue), Key length: \(aiAPIKey.count)")

                if isAIConfigured {
                    logger.log(.ai, "Requesting commit message", context: aiProvider.rawValue)
                    var diff = try await worker.runAction(args: ["diff", "--cached"], in: url)
                    
                    // If nothing is staged, we're likely in a "Quick Commit" flow.
                    // Provide the unstaged diff to the AI so it has context.
                    if diff.isEmpty && !status.isEmpty {
                        logger.log(.ai, "Staged diff is empty, trying unstaged diff for context")
                        diff = try await worker.runAction(args: ["diff"], in: url)
                        diffStat = try await worker.runAction(args: ["diff", "--stat"], in: url)
                        
                        // If still empty (e.g. only untracked files), provide the status list AND some content
                        if diff.isEmpty {
                            logger.log(.ai, "Unstaged diff also empty, reading untracked files content")
                            var untrackedContext = "New files (untracked):\n\(status)\n\nFile contents summary:\n"
                            let untrackedFiles = status.split(separator: "\n").compactMap { line -> String? in
                                guard line.count >= 4 else { return nil }
                                return String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                            }
                            
                            for file in untrackedFiles.prefix(5) { // Limit to first 5 files for brevity
                                if let content = try? await worker.runAction(args: ["show", ":\(file)"], in: url) {
                                    untrackedContext += "--- \(file) ---\n\(content.prefix(500))\n"
                                } else if let localContent = try? String(contentsOf: url.appendingPathComponent(file), encoding: .utf8) {
                                    untrackedContext += "--- \(file) ---\n\(localContent.prefix(500))\n"
                                }
                            }
                            diff = untrackedContext
                        }
                    }

                    if diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        logger.log(.ai, "No changes detected at all, skipping AI")
                        suggestedCommitMessage = ""
                        return
                    }

                    let logOutput = try await worker.runAction(args: ["log", "--oneline", "-10"], in: url)
                    let recentMessages = logOutput.split(separator: "\n").map { line in
                        let parts = line.split(separator: " ", maxSplits: 1)
                        return parts.count > 1 ? String(parts[1]) : String(line)
                    }

                    let message = try await aiClient.generateCommitMessage(
                        diff: diff,
                        diffStat: diffStat,
                        recentMessages: recentMessages,
                        branchName: currentBranch,
                        provider: aiProvider,
                        apiKey: aiAPIKey,
                        style: commitMessageStyle
                    )
                    logger.log(.ai, "Commit message generated OK")
                    suggestedCommitMessage = message
                } else {
                    suggestedCommitMessage = Self.generateCommitMessage(diffStat: diffStat, status: status)
                }
            } catch {
                if let aiErr = error as? AIError, case .quotaExceeded = aiErr {
                    aiQuotaExceeded = true
                }
                logger.log(.error, "AI commit message failed: \(error.localizedDescription)", context: aiProvider.rawValue, source: #function)
                // Fallback to heuristic on AI failure
                if let url = repositoryURL,
                   let diffStat = try? await worker.runAction(args: ["diff", "--cached", "--stat"], in: url),
                   let status = try? await worker.runAction(args: ["status", "--porcelain"], in: url) {
                    suggestedCommitMessage = Self.generateCommitMessage(diffStat: diffStat, status: status)
                } else {
                    suggestedCommitMessage = ""
                }
            }
        }
    }

    func suggestPRDescription() async -> (title: String, body: String)? {
        guard let url = repositoryURL, isAIConfigured else { return nil }

        isGeneratingAIMessage = true
        defer { isGeneratingAIMessage = false }

        do {
            logger.log(.ai, "Requesting PR description", context: aiProvider.rawValue)
            let commitLog = try await worker.runAction(
                args: ["log", "--oneline", "main..HEAD"],
                in: url
            )
            let diffStat = try await worker.runAction(
                args: ["diff", "--stat", "main..HEAD"],
                in: url
            )
            let result = try await aiClient.generatePRDescription(
                commitLog: commitLog,
                diffStat: diffStat,
                branchName: currentBranch,
                baseBranch: "main",
                provider: aiProvider,
                apiKey: aiAPIKey
            )
            logger.log(.ai, "PR description generated OK")
            return result
        } catch {
            logger.log(.error, "AI PR description failed: \(error.localizedDescription)", context: aiProvider.rawValue, source: #function)
            lastError = error.localizedDescription
            return nil
        }
    }

    func suggestStashMessage() {
        guard let url = repositoryURL, isAIConfigured else { return }

        aiTask?.cancel()
        aiTask = Task {
            isGeneratingAIMessage = true
            defer { isGeneratingAIMessage = false }

            do {
                logger.log(.ai, "Requesting stash message", context: aiProvider.rawValue)
                let diff = try await worker.runAction(args: ["diff"], in: url)
                let diffStat = try await worker.runAction(args: ["diff", "--stat"], in: url)
                let message = try await aiClient.generateStashMessage(
                    diff: diff,
                    diffStat: diffStat,
                    provider: aiProvider,
                    apiKey: aiAPIKey
                )
                logger.log(.ai, "Stash message generated OK")
                stashMessageInput = message
            } catch {
                logger.log(.error, "AI stash message failed: \(error.localizedDescription)", context: aiProvider.rawValue, source: #function)
                lastError = error.localizedDescription
            }
        }
    }

    func explainFileDiff(fileName: String, diff: String) {
        guard isAIConfigured else { return }

        aiTask?.cancel()
        aiTask = Task {
            isGeneratingAIMessage = true
            defer { isGeneratingAIMessage = false }

            do {
                logger.log(.ai, "Requesting diff explanation", context: "\(aiProvider.rawValue): \(fileName)")
                let explanation = try await aiClient.explainDiff(
                    fileDiff: diff,
                    fileName: fileName,
                    provider: aiProvider,
                    apiKey: aiAPIKey
                )
                logger.log(.ai, "Diff explanation generated OK")
                aiDiffExplanation = explanation
            } catch {
                logger.log(.error, "AI diff explanation failed: \(error.localizedDescription)", context: aiProvider.rawValue, source: #function)
                aiDiffExplanation = ""
                lastError = error.localizedDescription
            }
        }
    }

    // MARK: - Detailed Diff Explanation (Phase 2)

    func explainDiffDetailed(fileName: String, diff: String) {
        guard isAIConfigured else { return }

        explainDiffTask?.cancel()
        explainDiffTask = Task {
            isExplainingDiff = true
            defer { isExplainingDiff = false }

            do {
                let explanation = try await aiClient.explainDiffDetailed(
                    fileDiff: diff,
                    fileName: fileName,
                    provider: aiProvider,
                    apiKey: aiAPIKey
                )
                currentDiffExplanation = explanation
            } catch {
                currentDiffExplanation = nil
                lastError = error.localizedDescription
            }
        }
    }

    // MARK: - Code Review (Phase 3)

    func startCodeReview(source: String, target: String) {
        guard let url = repositoryURL else { return }

        codeReviewTask?.cancel()
        codeReviewTask = Task {
            isCodeReviewLoading = true
            isCodeReviewVisible = true
            codeReviewFiles = []

            // Get diff stat for file list
            let diffStatResult = try? git.run(args: ["diff", "--numstat", "\(target)...\(source)"], in: url)
            let diffStat = diffStatResult?.stdout ?? ""
            let files = parseDiffStatForCodeReview(diffStat, source: source, target: target, at: url)
            codeReviewFiles = files
            if let first = files.first { selectedReviewFileID = first.id }

            // Get commit count
            let logCountResult = try? git.run(args: ["rev-list", "--count", "\(target)...\(source)"], in: url)
            let commitCount = Int((logCountResult?.stdout ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

            recalculateCodeReviewStats(commitCount: commitCount)
            isCodeReviewLoading = false
        }
    }

    func reviewAllCodeReviewFiles() {
        guard isAIConfigured else { return }

        codeReviewTask?.cancel()
        codeReviewTask = Task {
            isCodeReviewLoading = true

            for i in codeReviewFiles.indices {
                guard !Task.isCancelled else { break }
                guard codeReviewFiles[i].findings.isEmpty else { continue }

                do {
                    let findings = try await aiClient.reviewFile(
                        fileDiff: codeReviewFiles[i].diff,
                        fileName: codeReviewFiles[i].path,
                        provider: aiProvider,
                        apiKey: aiAPIKey
                    )
                    codeReviewFiles[i].findings = findings
                    codeReviewFiles[i].isReviewed = true

                    // Also get detailed explanation
                    let explanation = try await aiClient.explainDiffDetailed(
                        fileDiff: codeReviewFiles[i].diff,
                        fileName: codeReviewFiles[i].path,
                        provider: aiProvider,
                        apiKey: aiAPIKey
                    )
                    codeReviewFiles[i].explanation = explanation
                } catch {
                    lastError = error.localizedDescription
                }
            }

            recalculateCodeReviewStats(commitCount: codeReviewStats.commitCount)
            isCodeReviewLoading = false
        }
    }

    func copyCodeReviewSummary() {
        var summary = "# Code Review: \(branchReviewSource) → \(branchReviewTarget)\n\n"
        summary += "Files: \(codeReviewStats.totalFiles) | "
        summary += "+\(codeReviewStats.totalAdditions)/-\(codeReviewStats.totalDeletions) | "
        summary += "Risk: \(codeReviewStats.overallRisk.label)\n\n"

        for file in codeReviewFiles where !file.findings.isEmpty {
            summary += "## \(file.path)\n"
            for finding in file.findings {
                summary += "- [\(finding.severity.rawValue)] \(finding.message)\n"
            }
            summary += "\n"
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
    }

    func exportCodeReviewMarkdown() {
        var md = "# Code Review\n\n"
        md += "**Source:** `\(branchReviewSource)` → **Target:** `\(branchReviewTarget)`\n\n"
        md += "| Metric | Value |\n|--------|-------|\n"
        md += "| Files | \(codeReviewStats.totalFiles) |\n"
        md += "| Additions | +\(codeReviewStats.totalAdditions) |\n"
        md += "| Deletions | -\(codeReviewStats.totalDeletions) |\n"
        md += "| Risk | \(codeReviewStats.overallRisk.label) |\n\n"

        for file in codeReviewFiles {
            md += "## \(file.path)\n\n"
            if let explanation = file.explanation {
                md += "**Intent:** \(explanation.intent)\n\n"
                md += "**Risks:** \(explanation.risks)\n\n"
            }
            if !file.findings.isEmpty {
                md += "### Findings\n\n"
                for finding in file.findings {
                    let icon = finding.severity == .critical ? "🔴" : finding.severity == .warning ? "🟡" : "🔵"
                    md += "- \(icon) \(finding.message)\n"
                }
                md += "\n"
            }
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "code-review-\(branchReviewSource)-\(branchReviewTarget).md"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? md.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func parseDiffStatForCodeReview(_ output: String, source: String, target: String, at url: URL) -> [CodeReviewFile] {
        // Parse --numstat output: additions\tdeletions\tfilename
        output.split(separator: "\n").compactMap { line -> CodeReviewFile? in
            let parts = line.split(separator: "\t")
            guard parts.count >= 3 else { return nil }
            let additions = Int(parts[0]) ?? 0
            let deletions = Int(parts[1]) ?? 0
            let path = String(parts[2])

            // Determine file status
            let status: FileChangeStatus
            if additions > 0 && deletions == 0 { status = .added }
            else if additions == 0 && deletions > 0 { status = .deleted }
            else { status = .modified }

            // Get per-file diff
            let diffResult = try? git.run(args: ["diff", "\(target)...\(source)", "--", path], in: url)
            let diff = diffResult?.stdout ?? ""
            let hunks = Self.parseDiffHunks(diff)

            return CodeReviewFile(
                path: path,
                status: status,
                additions: additions,
                deletions: deletions,
                diff: diff,
                hunks: hunks
            )
        }
    }

    private func recalculateCodeReviewStats(commitCount: Int) {
        let allFindings = codeReviewFiles.flatMap(\.findings)
        codeReviewStats = CodeReviewStats(
            totalFiles: codeReviewFiles.count,
            totalAdditions: codeReviewFiles.reduce(0) { $0 + $1.additions },
            totalDeletions: codeReviewFiles.reduce(0) { $0 + $1.deletions },
            commitCount: commitCount,
            criticalCount: allFindings.filter { $0.severity == .critical }.count,
            warningCount: allFindings.filter { $0.severity == .warning }.count,
            suggestionCount: allFindings.filter { $0.severity == .suggestion }.count
        )
    }

    // MARK: - PR Review Queue (Phase 4)

    func openPRInCodeReview(_ item: PRReviewItem) {
        branchReviewSource = item.pr.headBranch
        branchReviewTarget = item.pr.baseBranch
        if !item.pr.headBranch.isEmpty && !item.pr.baseBranch.isEmpty {
            startCodeReview(source: item.pr.headBranch, target: item.pr.baseBranch)
        }
    }

    func reviewAllPRs() {
        guard isAIConfigured, let url = repositoryURL else { return }

        for i in prReviewQueue.indices where prReviewQueue[i].status == .pending {
            prReviewQueue[i].status = .reviewing

            let item = prReviewQueue[i]
            let idx = i
            Task {
                do {
                    // Get the diff for this PR
                    let remoteResult = try? git.run(args: ["remote", "get-url", "origin"], in: url)
            let remote = (remoteResult?.stdout ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let ghRemote = GitHubClient.parseRemote(remote) else { return }

                    let diff = await githubClient.fetchPRDiff(remote: ghRemote, prNumber: item.pr.number) ?? ""
                    let findings = try await aiClient.reviewBranch(
                        diff: diff,
                        diffStat: "",
                        sourceBranch: item.pr.headBranch,
                        targetBranch: item.pr.baseBranch,
                        provider: aiProvider,
                        apiKey: aiAPIKey
                    )

                    prReviewQueue[idx].findings = findings
                    prReviewQueue[idx].status = findings.contains(where: { $0.severity == .critical || $0.severity == .warning }) ? .reviewed : .clean
                    prReviewQueue[idx].reviewedAt = Date()

                    // Notify
                    let repoName = url.lastPathComponent
                    await ntfyClient.sendIfEnabled(
                        event: .prAutoReviewComplete,
                        title: L10n("PR #\(item.pr.number) reviewed"),
                        body: "\(item.pr.title) — \(findings.count) findings",
                        repoName: repoName
                    )
                } catch {
                    prReviewQueue[idx].status = .pending
                }
            }
        }
    }

    func refreshPRReviewQueue() {
        guard let url = repositoryURL else { return }

        prPollingTask?.cancel()
        prPollingTask = Task {
            let remoteResult = try? git.run(args: ["remote", "get-url", "origin"], in: url)
            let remote = (remoteResult?.stdout ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let ghRemote = GitHubClient.parseRemote(remote) else { return }

            let prs = await githubClient.fetchPRsRequestingMyReview(remote: ghRemote)
            let existingIDs = Set(prReviewQueue.map(\.pr.id))

            for pr in prs where !existingIDs.contains(pr.id) {
                prReviewQueue.append(PRReviewItem(pr: pr))
            }

            // Remove PRs no longer requesting review
            let currentIDs = Set(prs.map(\.id))
            prReviewQueue.removeAll { !currentIDs.contains($0.pr.id) }

            // Auto-review if enabled
            let autoReview = UserDefaults.standard.bool(forKey: "zion.autoReviewAssignedPRs")
            if autoReview && isAIConfigured {
                reviewAllPRs()
            }
        }
    }

    // MARK: - AI Smart Conflict Resolution

    func resolveConflictWithAI(region: ConflictRegion, fileName: String) {
        guard let url = repositoryURL, isAIConfigured else { return }

        aiTask?.cancel()
        aiTask = Task {
            isGeneratingAIMessage = true
            defer { isGeneratingAIMessage = false }

            do {
                logger.log(.ai, "Requesting conflict resolution", context: "\(aiProvider.rawValue): \(fileName)")
                // Get surrounding context from the file
                var context = ""
                if let fileContent = try? String(contentsOf: url.appendingPathComponent(fileName), encoding: .utf8) {
                    context = String(fileContent.prefix(3000))
                }

                let resolved = try await aiClient.resolveConflict(
                    oursLines: region.oursLines,
                    theirsLines: region.theirsLines,
                    oursLabel: region.oursLabel,
                    theirsLabel: region.theirsLabel,
                    surroundingContext: context,
                    fileName: fileName,
                    provider: aiProvider,
                    apiKey: aiAPIKey
                )
                logger.log(.ai, "Conflict resolution generated OK")
                aiConflictResolution = resolved
            } catch {
                logger.log(.error, "AI conflict resolution failed: \(error.localizedDescription)", context: aiProvider.rawValue, source: #function)
                aiConflictResolution = ""
                lastError = error.localizedDescription
            }
        }
    }

    // MARK: - AI Code Review

    func reviewStagedChanges() {
        guard let url = repositoryURL, isAIConfigured else { return }

        aiTask?.cancel()
        aiTask = Task {
            isGeneratingAIMessage = true
            defer { isGeneratingAIMessage = false }

            do {
                logger.log(.ai, "Requesting code review", context: aiProvider.rawValue)
                let diff = try await worker.runAction(args: ["diff", "--cached"], in: url)
                guard !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    aiReviewFindings = [ReviewFinding(severity: .suggestion, file: "general", message: L10n("Nenhuma alteracao staged para revisar."))]
                    isReviewVisible = true
                    return
                }
                let diffStat = try await worker.runAction(args: ["diff", "--cached", "--stat"], in: url)
                let findings = try await aiClient.reviewDiff(
                    diff: diff,
                    diffStat: diffStat,
                    branchName: currentBranch,
                    provider: aiProvider,
                    apiKey: aiAPIKey
                )
                logger.log(.ai, "Code review generated OK: \(findings.count) findings")
                aiReviewFindings = findings
                isReviewVisible = true
            } catch {
                if let aiErr = error as? AIError, case .quotaExceeded = aiErr {
                    aiQuotaExceeded = true
                }
                logger.log(.error, "AI code review failed: \(error.localizedDescription)", context: aiProvider.rawValue, source: #function)
                lastError = error.localizedDescription
            }
        }
    }

    // MARK: - AI Changelog Generator

    func generateChangelog() {
        guard let url = repositoryURL, isAIConfigured else { return }
        let from = changelogFromRef.isEmpty ? "HEAD~20" : changelogFromRef
        let to = changelogToRef.isEmpty ? "HEAD" : changelogToRef

        aiTask?.cancel()
        aiTask = Task {
            isGeneratingAIMessage = true
            defer { isGeneratingAIMessage = false }

            do {
                logger.log(.ai, "Requesting changelog", context: "\(aiProvider.rawValue): \(from)..\(to)")
                let commitLog = try await worker.runAction(args: ["log", "--oneline", "\(from)..\(to)"], in: url)
                guard !commitLog.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    aiChangelog = L10n("Nenhum commit encontrado no intervalo.")
                    isChangelogSheetVisible = true
                    return
                }
                let changelog = try await aiClient.generateChangelog(
                    commitLog: commitLog,
                    fromRef: from,
                    toRef: to,
                    provider: aiProvider,
                    apiKey: aiAPIKey
                )
                logger.log(.ai, "Changelog generated OK")
                aiChangelog = changelog
                isChangelogSheetVisible = true
            } catch {
                if let aiErr = error as? AIError, case .quotaExceeded = aiErr {
                    aiQuotaExceeded = true
                }
                logger.log(.error, "AI changelog failed: \(error.localizedDescription)", context: aiProvider.rawValue, source: #function)
                lastError = error.localizedDescription
            }
        }
    }

    // MARK: - AI Semantic Search

    func semanticSearchCommits(query: String) {
        guard let url = repositoryURL, isAIConfigured else { return }

        aiTask?.cancel()
        aiTask = Task {
            isGeneratingAIMessage = true
            defer { isGeneratingAIMessage = false }

            do {
                logger.log(.ai, "Requesting semantic search", context: "\(aiProvider.rawValue): \(query)")
                let commitLog = try await worker.runAction(args: ["log", "--oneline", "-200"], in: url)
                let hashes = try await aiClient.semanticSearch(
                    query: query,
                    commitLog: commitLog,
                    provider: aiProvider,
                    apiKey: aiAPIKey
                )
                logger.log(.ai, "Semantic search OK: \(hashes.count) results")
                aiSemanticSearchResults = hashes
            } catch {
                if let aiErr = error as? AIError, case .quotaExceeded = aiErr {
                    aiQuotaExceeded = true
                }
                logger.log(.error, "AI semantic search failed: \(error.localizedDescription)", context: aiProvider.rawValue, source: #function)
                aiSemanticSearchResults = []
                lastError = error.localizedDescription
            }
        }
    }

    func clearSemanticSearch() {
        aiSemanticSearchResults = []
        isSemanticSearchActive = false
    }

    // MARK: - AI Branch Summarizer

    func summarizeBranch(_ branchName: String) {
        guard let url = repositoryURL, isAIConfigured else { return }

        aiTask?.cancel()
        aiTask = Task {
            isGeneratingAIMessage = true
            defer { isGeneratingAIMessage = false }

            do {
                logger.log(.ai, "Requesting branch summary", context: "\(aiProvider.rawValue): \(branchName)")
                let commitLog = try await worker.runAction(args: ["log", "--oneline", "HEAD...\(branchName)", "--", "--max-count=50"], in: url)
                let diffStat = try await worker.runAction(args: ["diff", "--stat", "HEAD...\(branchName)"], in: url)
                let summary = try await aiClient.summarizeBranch(
                    branchName: branchName,
                    commitLog: commitLog.isEmpty ? branchName : commitLog,
                    diffStat: diffStat,
                    provider: aiProvider,
                    apiKey: aiAPIKey
                )
                logger.log(.ai, "Branch summary generated OK")
                branchSummaries[branchName] = summary
            } catch {
                logger.log(.error, "AI branch summary failed: \(error.localizedDescription)", context: aiProvider.rawValue, source: #function)
                lastError = error.localizedDescription
            }
        }
    }

    func reviewBranch(source: String, target: String) {
        guard let url = repositoryURL, isAIConfigured else { return }

        aiTask?.cancel()
        aiTask = Task {
            isBranchReviewLoading = true
            defer { isBranchReviewLoading = false }

            do {
                logger.log(.ai, "Requesting branch review", context: "\(aiProvider.rawValue): \(source)..\(target)")
                let diff = try await worker.runAction(args: ["diff", "\(target)...\(source)"], in: url)
                let diffStat = try await worker.runAction(args: ["diff", "--stat", "\(target)...\(source)"], in: url)
                
                guard !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    branchReviewFindings = [ReviewFinding(severity: .suggestion, file: "general", message: L10n("Nenhuma diferenca entre as branches."))]
                    return
                }

                let findings = try await aiClient.reviewBranch(
                    diff: diff,
                    diffStat: diffStat,
                    sourceBranch: source,
                    targetBranch: target,
                    provider: aiProvider,
                    apiKey: aiAPIKey
                )
                logger.log(.ai, "Branch review OK: \(findings.count) findings")
                branchReviewFindings = findings
            } catch {
                logger.log(.error, "AI branch review failed: \(error.localizedDescription)", context: aiProvider.rawValue, source: #function)
                lastError = error.localizedDescription
            }
        }
    }

    // MARK: - AI Blame Explainer

    func explainBlameEntry(entry: BlameEntry, fileName: String) {
        guard let url = repositoryURL, isAIConfigured else { return }

        aiTask?.cancel()
        aiTask = Task {
            isGeneratingAIMessage = true
            defer { isGeneratingAIMessage = false }

            do {
                logger.log(.ai, "Requesting blame explanation", context: "\(aiProvider.rawValue): \(entry.commitHash)")
                let commitDiff = try await worker.runAction(args: ["show", entry.commitHash, "--", fileName], in: url)
                let commitSubject = try await worker.runAction(args: ["log", "-1", "--format=%s", entry.commitHash], in: url)
                let explanation = try await aiClient.explainBlameRegion(
                    commitHash: entry.commitHash,
                    fileName: fileName,
                    commitDiff: commitDiff,
                    commitSubject: commitSubject,
                    regionContent: entry.content,
                    provider: aiProvider,
                    apiKey: aiAPIKey
                )
                logger.log(.ai, "Blame explanation generated OK")
                aiBlameExplanation = explanation
                aiBlameEntryID = entry.id
            } catch {
                logger.log(.error, "AI blame explanation failed: \(error.localizedDescription)", context: aiProvider.rawValue, source: #function)
                aiBlameExplanation = ""
                aiBlameEntryID = nil
                lastError = error.localizedDescription
            }
        }
    }

    // MARK: - AI Commit Split Advisor

    func suggestCommitSplit() {
        guard let url = repositoryURL, isAIConfigured else { return }

        aiTask?.cancel()
        aiTask = Task {
            isGeneratingAIMessage = true
            defer { isGeneratingAIMessage = false }

            do {
                logger.log(.ai, "Requesting commit split suggestion", context: aiProvider.rawValue)
                let diff = try await worker.runAction(args: ["diff", "--cached"], in: url)
                guard !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    aiCommitSplitSuggestions = []
                    return
                }
                let diffStat = try await worker.runAction(args: ["diff", "--cached", "--stat"], in: url)
                let suggestions = try await aiClient.suggestCommitSplit(
                    diff: diff,
                    diffStat: diffStat,
                    provider: aiProvider,
                    apiKey: aiAPIKey
                )
                logger.log(.ai, "Commit split suggestions OK: \(suggestions.count) commits")
                aiCommitSplitSuggestions = suggestions
                isSplitVisible = true
            } catch {
                if let aiErr = error as? AIError, case .quotaExceeded = aiErr {
                    aiQuotaExceeded = true
                }
                logger.log(.error, "AI commit split failed: \(error.localizedDescription)", context: aiProvider.rawValue, source: #function)
                lastError = error.localizedDescription
            }
        }
    }

    static func generateCommitMessage(diffStat: String, status: String) -> String {
        let lines = status.split(separator: "\n").map(String.init)
        guard !lines.isEmpty else { return "" }

        var added = 0, modified = 0, deleted = 0
        var paths: [String] = []
        for line in lines {
            // git status --porcelain is exactly "XY path"
            // X (index 0), Y (index 1), space (index 2), path (index 3...)
            guard line.count >= 4 else { continue }
            let indexStatus = String(line.prefix(1))
            let workTreeStatus = String(line.dropFirst(1).prefix(1))
            let file = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            
            paths.append(file)
            
            if indexStatus == "A" || indexStatus == "?" {
                added += 1
            } else if workTreeStatus == "M" || indexStatus == "M" {
                modified += 1
            } else if workTreeStatus == "D" || indexStatus == "D" {
                deleted += 1
            } else {
                modified += 1
            }
        }

        let scope: String
        let commonComponents = paths.compactMap { $0.split(separator: "/").dropLast().first }.map(String.init)
        if let most = commonComponents.mostFrequent() {
            scope = "(\(most))"
        } else {
            scope = ""
        }

        let type: String
        if added > 0 && modified == 0 && deleted == 0 {
            type = "feat"
        } else if deleted > 0 && added == 0 && modified == 0 {
            type = "chore"
        } else if paths.allSatisfy({ $0.hasSuffix("Test.swift") || $0.hasSuffix("Tests.swift") || $0.contains("test") }) {
            type = "test"
        } else if paths.allSatisfy({ $0.hasSuffix(".md") || $0.hasSuffix(".txt") }) {
            type = "docs"
        } else {
            type = modified > added ? "fix" : "feat"
        }

        let description: String
        let fileCount = lines.count
        if fileCount == 1 {
            let fileName = URL(fileURLWithPath: paths[0]).deletingPathExtension().lastPathComponent
            description = added > 0 ? "add \(fileName)" : "update \(fileName)"
        } else {
            description = "\(type == "feat" ? "add" : "update") \(fileCount) files"
        }

        return "\(type)\(scope): \(description)"
    }

    // MARK: - Commit Signing Visualization

    func loadSignatureStatuses() {
        guard let url = repositoryURL else { return }

        Task {
            do {
                let output = try await worker.runAction(
                    args: ["log", "--format=%H %G?", "-n", "100"],
                    in: url
                )
                var statuses: [String: String] = [:]
                for line in output.split(separator: "\n") {
                    let parts = line.split(separator: " ", maxSplits: 1)
                    if parts.count == 2 {
                        statuses[String(parts[0])] = String(parts[1])
                    }
                }
                commitSignatureStatus = statuses
            } catch {
                logger.log(.warn, "Failed to load signature statuses: \(error.localizedDescription)", source: #function)
                commitSignatureStatus = [:]
            }
        }
    }

    func signatureStatusFor(_ commitHash: String) -> String? {
        commitSignatureStatus[commitHash]
    }

    // MARK: - Background Fetch

    func startBackgroundFetch() {
        backgroundFetchTask?.cancel()
        backgroundFetchTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000) // 60s
                if Task.isCancelled { break }
                await checkBehindRemote()
                await checkPRReviewRequests()
            }
        }
    }

    private func checkBehindRemote() async {
        guard let url = repositoryURL else { return }
        do {
            // Dry-run fetch to check for updates
            let _ = try await worker.runAction(args: ["fetch", "--dry-run"], in: url)
            // Check how many commits behind
            let output = try await worker.runAction(
                args: ["rev-list", "--count", "HEAD..@{upstream}"],
                in: url
            )
            let newCount = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            behindRemoteCount = newCount
            if newCount > 0 && lastNotifiedBehindCount == 0 {
                await ntfyClient.sendIfEnabled(
                    event: .newRemoteCommits,
                    title: L10n("ntfy.event.newRemoteCommits"),
                    body: "\(newCount) commits behind upstream",
                    repoName: url.lastPathComponent
                )
            }
            lastNotifiedBehindCount = newCount
        } catch {
            logger.log(.info, "Behind remote check failed (expected if no upstream): \(error.localizedDescription)", source: #function)
            behindRemoteCount = 0
            lastNotifiedBehindCount = 0
        }
    }

    private func checkPRReviewRequests() async {
        guard let remote = detectGitHubRemote() else { return }
        let prs = await githubClient.fetchPRsRequestingMyReview(remote: remote)
        for pr in prs {
            if !notifiedReviewRequestPRIDs.contains(pr.id) {
                notifiedReviewRequestPRIDs.insert(pr.id)
                await ntfyClient.sendIfEnabled(
                    event: .prReviewRequested,
                    title: L10n("ntfy.event.prReviewRequested"),
                    body: "#\(pr.number) \(pr.title)",
                    repoName: repositoryURL?.lastPathComponent ?? ""
                )
            }
        }
    }

    // MARK: - Background Repo Persistence

    private func startBackgroundMonitor(for url: URL) {
        guard var state = backgroundRepoStates[url] else { return }

        state.fileWatcher.onRepositoryChanged = { [weak self] in
            Task { [weak self] in
                await self?.updateChangedFileCount(for: url)
            }
        }
        state.fileWatcher.watch(directory: url)

        // Periodic check every 30s (catches changes FileWatcher might miss)
        state.monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if Task.isCancelled { break }
                await self?.updateChangedFileCount(for: url)
            }
        }

        backgroundRepoStates[url] = state
    }

    private func updateChangedFileCount(for url: URL) async {
        do {
            let output = try await worker.runAction(
                args: ["status", "--porcelain"],
                in: url
            )
            let count = output.split(separator: "\n").count
            backgroundRepoChangedFiles[url] = count
        } catch {
            // Silently fail — repo may be unavailable
        }
    }

    func cleanupAllBackgroundStates() {
        for (_, state) in backgroundRepoStates {
            state.monitorTask?.cancel()
            state.fileWatcher.stop()
            for tab in state.terminalTabs {
                for session in tab.allSessions() {
                    session.killCachedProcess()
                }
            }
        }
        backgroundRepoStates.removeAll()
        backgroundRepoChangedFiles.removeAll()
    }

    // MARK: - Repository Statistics

    func loadRepositoryStats() {
        guard let url = repositoryURL else { return }

        Task {
            do {
                // Total commits
                let countOutput = try await worker.runAction(args: ["rev-list", "--count", "HEAD"], in: url)
                let totalCommits = Int(countOutput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

                // Contributors
                let shortlog = try await worker.runAction(args: ["shortlog", "-sne", "HEAD"], in: url)
                let contributors = shortlog.split(separator: "\n").compactMap { line -> ContributorStat? in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    let parts = trimmed.split(separator: "\t", maxSplits: 1)
                    guard parts.count == 2 else { return nil }
                    let count = Int(parts[0].trimmingCharacters(in: .whitespaces)) ?? 0
                    let nameEmail = String(parts[1])
                    // Parse "Name <email>"
                    var name = nameEmail
                    var email = ""
                    if let emailRange = nameEmail.range(of: "<(.+?)>", options: .regularExpression) {
                        email = String(nameEmail[emailRange]).replacingOccurrences(of: "<", with: "").replacingOccurrences(of: ">", with: "")
                        name = String(nameEmail[..<emailRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                    }
                    return ContributorStat(name: name, email: email, commitCount: count)
                }

                // Language breakdown by file extension
                let files = try await worker.runAction(args: ["ls-files"], in: url)
                var extCount: [String: Int] = [:]
                for file in files.split(separator: "\n") {
                    let ext = URL(fileURLWithPath: String(file)).pathExtension.lowercased()
                    if !ext.isEmpty {
                        extCount[ext, default: 0] += 1
                    }
                }
                let totalFiles = max(1, extCount.values.reduce(0, +))
                let languages = extCount.sorted { $0.value > $1.value }.prefix(10).map { ext, count in
                    LanguageStat(language: Self.languageName(for: ext), fileCount: count,
                                percentage: Double(count) / Double(totalFiles) * 100)
                }

                // Date range
                let firstDate = try? await worker.runAction(args: ["log", "--reverse", "--format=%ci", "-1"], in: url)
                let lastDate = try? await worker.runAction(args: ["log", "--format=%ci", "-1"], in: url)

                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"

                repoStats = RepositoryStats(
                    totalCommits: totalCommits,
                    totalBranches: branches.count,
                    totalTags: tags.count,
                    contributors: contributors,
                    languageBreakdown: languages,
                    firstCommitDate: firstDate.flatMap { dateFormatter.date(from: $0.trimmingCharacters(in: .whitespacesAndNewlines)) },
                    lastCommitDate: lastDate.flatMap { dateFormatter.date(from: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                )
            } catch {
                logger.log(.warn, "Failed to load repo stats: \(error.localizedDescription)", source: #function)
                repoStats = nil
            }
        }
    }

    private static func languageName(for ext: String) -> String {
        let map: [String: String] = [
            "swift": "Swift", "ts": "TypeScript", "tsx": "TypeScript", "js": "JavaScript",
            "jsx": "JavaScript", "py": "Python", "rb": "Ruby", "go": "Go", "rs": "Rust",
            "java": "Java", "kt": "Kotlin", "c": "C", "cpp": "C++", "h": "C/C++ Header",
            "cs": "C#", "php": "PHP", "html": "HTML", "css": "CSS", "scss": "SCSS",
            "json": "JSON", "yaml": "YAML", "yml": "YAML", "md": "Markdown",
            "sql": "SQL", "sh": "Shell", "bash": "Shell", "zsh": "Shell",
            "xml": "XML", "toml": "TOML", "lock": "Lock", "liquid": "Liquid"
        ]
        return map[ext] ?? ext.uppercased()
    }

    private func defaultCommitLimit(for reference: String?) -> Int {
        if let reference, !reference.clean.isEmpty {
            return defaultCommitLimitFocused
        }
        return defaultCommitLimitAll
    }

    private func clearError() {
        lastError = nil
    }

    private func handleError(_ error: Error, source: String = #function) {
        lastError = error.localizedDescription
        statusMessage = error.localizedDescription
        logger.log(.error, error.localizedDescription, source: source)
    }

    private func startFileWatcher(for url: URL) {
        fileWatcher.onFileChanged = { [weak self] in
            guard let self else { return }
            // Reload the currently open file if it changed on disk
            if let file = self.selectedCodeFile {
                if let content = try? String(contentsOf: file.url, encoding: .utf8) {
                    if content != self.codeFileContent {
                        self.codeFileContent = content
                        self.originalFileContents[file.id] = content
                        self.unsavedFiles.remove(file.id)
                    }
                }
            }
        }
        fileWatcher.onRepositoryChanged = { [weak self] in
            self?.refreshRepository(setBusy: false)
            self?.refreshFileTree()
        }
        fileWatcher.watch(directory: url)
    }

    private func startAutoRefreshTimer() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task {
            while !Task.isCancelled {
                // Wait for 30 seconds
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                
                if Task.isCancelled { break }
                
                // Refresh without showing busy indicator to avoid UI flickering
                refreshRepository(setBusy: false)
            }
        }
    }

    deinit {
        autoRefreshTask?.cancel()
        let states = backgroundRepoStates
        for (_, state) in states {
            state.monitorTask?.cancel()
        }
        Task { @MainActor in
            for (_, state) in states {
                state.fileWatcher.stop()
                for tab in state.terminalTabs {
                    for session in tab.allSessions() {
                        session.killCachedProcess()
                    }
                }
            }
        }
    }
}

// MARK: - Background Repo State

struct BackgroundRepoState {
    var terminalTabs: [TerminalPaneNode]
    var activeTabID: UUID?
    var focusedSessionID: UUID?
    var fileWatcher: FileWatcher
    var monitorTask: Task<Void, Never>?
}
