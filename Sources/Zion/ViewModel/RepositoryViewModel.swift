import Foundation
import SwiftUI
import CryptoKit
import UniformTypeIdentifiers
import IOKit.pwr_mgt
@preconcurrency import SwiftTerm

@Observable @MainActor
final class RepositoryViewModel {
    enum CommitDetailTab {
        case details
        case aiReview
    }

    enum RefreshOrigin: String {
        case userInitiated
        case autoTimer
        case fileWatcher
        case repositorySwitch

        var usesSilentCommitDetails: Bool {
            switch self {
            case .autoTimer, .fileWatcher, .repositorySwitch:
                return true
            case .userInitiated:
                return false
            }
        }
    }

    enum CommitDetailsLoadPolicy {
        case interactive
        case silent
    }

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
    var mergedBranchesPreview: [String] = []
    var branchTree: [BranchTreeNode] = []
    var focusedBranch: String?
    var inferBranchOrigins: Bool = true
    var hasMoreCommits: Bool = false
    var tags: [String] = []
    var stashes: [String] = []
    var selectedStash: String = ""
    var recoverySnapshots: [RecoverySnapshot] = []
    var isRecoverySnapshotsLoading: Bool = false
    var recoverySnapshotsStatus: String = ""
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
    var selectedCommitFile: String?
    var currentCommitFileDiff: String = ""
    var currentCommitFileDiffHunks: [DiffHunk] = []

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
    @ObservationIgnored let clipboardMonitor = ClipboardMonitor()
    @ObservationIgnored var _isReloadingExpandedDirs = false
    @ObservationIgnored var terminalSendCallbacks: [UUID: (Data) -> Void] = [:]

    // Avatar cache (Gravatar)
    @ObservationIgnored var avatarCache: [String: NSImage] = [:]
    @ObservationIgnored var avatarDownloadTasks: Set<String> = []

    // Hunk diff state
    var currentFileDiffHunks: [DiffHunk] = []
    var selectedHunkLines: Set<UUID> = []

    // Blame state
    var isBlameVisible: Bool = false
    var blameEntries: [BlameEntry] = []
    @ObservationIgnored var blameTask: Task<Void, Never>?

    // Reflog state
    var reflogEntries: [ReflogEntry] = []
    var isReflogVisible: Bool = false
    @ObservationIgnored var reflogTask: Task<Void, Never>?

    // Interactive rebase state
    var isRebaseSheetVisible: Bool = false
    var rebaseItems: [RebaseItem] = []
    var rebaseBaseRef: String = ""

    // Navigation signals (consumed by ContentView to switch tabs)
    var navigateToGraphRequested: Bool = false
    var navigateToCodeRequested: Bool = false
    var nextSectionAfterRepositoryOpen: AppSection?
    var pendingExternalFiles: [URL] = []

    // Git Hosting Provider integration
    var pullRequests: [HostedPRInfo] = []
    var isPRSheetVisible: Bool = false
    @ObservationIgnored let githubClient = GitHubClient()
    @ObservationIgnored let gitlabClient = GitLabClient()
    @ObservationIgnored let bitbucketClient = BitbucketClient()
    @ObservationIgnored var hostingProvider: (any GitHostingProvider)?
    @ObservationIgnored let ntfyClient = NtfyClient()
    @ObservationIgnored var prTask: Task<Void, Never>?

    // Branch review
    var isBranchReviewSheetVisible: Bool = false
    var branchReviewFindings: [ReviewFinding] = []
    var branchReviewSource: String = ""
    var branchReviewTarget: String = ""
    var isBranchReviewLoading: Bool = false
    var githubUsername: String = ""
    @ObservationIgnored private var lastNotifiedPRReviewIDs: Set<Int> = []

    var localBranchOptions: [String] {
        branchInfos
            .filter { !$0.isRemote }
            .map(\.name)
            .sorted()
    }

    var remoteBranchOptions: [String] {
        branchInfos
            .filter(\.isRemote)
            .map(\.name)
            .sorted()
    }

    // Code Review (Phase 3)
    var isCodeReviewVisible: Bool = false
    var codeReviewFiles: [CodeReviewFile] = []
    var selectedReviewFileID: UUID?
    var isCodeReviewLoading: Bool = false
    var codeReviewStats: CodeReviewStats = CodeReviewStats(totalFiles: 0, totalAdditions: 0, totalDeletions: 0, commitCount: 0, criticalCount: 0, warningCount: 0, suggestionCount: 0)
    @ObservationIgnored var codeReviewTask: Task<Void, Never>?

    // PR Review Queue
    var prReviewQueue: [PRReviewItem] = []
    @ObservationIgnored var prPollingTask: Task<Void, Never>?

    // PR Comments & Review (inline review)
    var prComments: [PRComment] = []
    var pendingReviewComments: [PRReviewDraftComment] = []
    var isPRReviewSubmitSheetVisible: Bool = false

    // Diff Explanation (Phase 2)
    var currentDiffExplanation: DiffExplanation?
    var isExplainingDiff: Bool = false
    @ObservationIgnored var explainDiffTask: Task<Void, Never>?

    // Auto-explain setting
    var autoExplainDiffs: Bool = false {
        didSet { UserDefaults.standard.set(autoExplainDiffs, forKey: "zion.autoExplainDiffs") }
    }
    var diffExplanationDepth: DiffExplanationDepth = .quick {
        didSet { UserDefaults.standard.set(diffExplanationDepth.rawValue, forKey: "zion.diffExplanationDepth") }
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
    var commitReviewCache: [String: [ReviewFinding]] = [:]
    var reviewingCommitID: String?
    var selectedCommitDetailTab: CommitDetailTab = .details
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

    // Pre-Commit AI Review Gate
    var preCommitReviewEnabled: Bool = false {
        didSet { UserDefaults.standard.set(preCommitReviewEnabled, forKey: "zion.preCommitReview") }
    }
    var aiTransferSupportHintsEnabled: Bool = true {
        didSet { UserDefaults.standard.set(aiTransferSupportHintsEnabled, forKey: "zion.aiTransferSupportHints") }
    }
    var preCommitReviewPending: Bool = false
    @ObservationIgnored var preCommitDiffHash: String = ""

    // File History
    var fileHistoryEntries: [FileHistoryEntry] = []
    var isFileHistoryVisible: Bool = false
    var isFileHistoryLoading: Bool = false
    @ObservationIgnored var fileHistoryTask: Task<Void, Never>?
    @ObservationIgnored var recoverySnapshotsTask: Task<Void, Never>?
    @ObservationIgnored var recoverySnapshotsRepositoryPath: String?

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
    @ObservationIgnored var aiTask: Task<Void, Never>?

    @ObservationIgnored var _cachedAIKey: String?
    @ObservationIgnored var _cachedAIKeyProvider: AIProvider?
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
    var aheadRemoteCount: Int = 0
    var showPushDivergenceWarning: Bool = false
    var pushDivergenceState: PushDivergenceState = .clear
    @ObservationIgnored var backgroundFetchTask: Task<Void, Never>?
    @ObservationIgnored var lastNotifiedBehindCount: Int = 0
    @ObservationIgnored var notifiedReviewRequestPRIDs: Set<Int> = []
    @ObservationIgnored var autoFetchCredentialFailures: Int = 0
    @ObservationIgnored var autoFetchSuspendedUntil: Date?

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

    var ntfyLocalNotificationsEnabled: Bool = true {
        didSet { UserDefaults.standard.set(ntfyLocalNotificationsEnabled, forKey: "zion.ntfy.localNotifications") }
    }

    var isNtfyConfigured: Bool { !ntfyTopic.isEmpty }

    // Mobile Remote Access
    var isMobileAccessEnabled: Bool = false {
        didSet { UserDefaults.standard.set(isMobileAccessEnabled, forKey: "zion.mobileAccess.enabled") }
    }
    var isMobileAccessLANMode: Bool = false {
        didSet { UserDefaults.standard.set(isMobileAccessLANMode, forKey: "zion.mobileAccess.lanMode") }
    }
    var mobileAccessConnectionState: RemoteAccessConnectionState = .disabled
    var mobileAccessTunnelURL: String = ""
    var mobileAccessQRImage: NSImage?
    var pairedDevices: [PairedDevice] = []
    @ObservationIgnored var remoteAccessServer: RemoteAccessServer?
    @ObservationIgnored var tunnelManager: CloudflareTunnelManager?
    @ObservationIgnored var terminalOutputBuffers: [UUID: Data] = [:]
    @ObservationIgnored var screenUpdateDebounceTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored var screenUpdateThrottleDeadlines: [UUID: ContinuousClock.Instant] = [:]
    @ObservationIgnored var heartbeatTask: Task<Void, Never>?
    @ObservationIgnored var isSwitchingMode = false
    @ObservationIgnored var hasEnsuredRemoteTerminals = false
    @ObservationIgnored var sleepAssertionID: IOPMAssertionID = 0
    @ObservationIgnored var sleepTimerTask: Task<Void, Never>?
    @ObservationIgnored var wakeObserver: NSObjectProtocol?

    // Background repo persistence (terminal sessions + change badges)
    @ObservationIgnored var backgroundRepoStates: [URL: BackgroundRepoState] = [:]
    var backgroundRepoChangedFiles: [URL: Int] = [:]

    // Repository statistics
    var repoStats: RepositoryStats?
    var isGitAvailable: Bool = true
    var showGitNotFoundAlert: Bool = false

    // Conflict resolution state
    var conflictedFiles: [ConflictFile] = []
    var selectedConflictFile: String?
    var conflictBlocks: [ConflictBlock] = []
    var isConflictViewVisible: Bool = false
    @ObservationIgnored var conflictTask: Task<Void, Never>?
    @ObservationIgnored var commitStatsTask: Task<Void, Never>?

    // Clone state
    var isCloneSheetVisible: Bool = false
    var cloneProgress: String = ""
    var isCloning: Bool = false
    var cloneError: String?
    @ObservationIgnored var cloneTask: Task<Void, Never>?
    @ObservationIgnored var cloneProcess: Process?
    var isGitAuthPromptVisible: Bool = false
    var gitAuthContext: GitAuthContext?
    @ObservationIgnored var gitAuthPromptContinuation: CheckedContinuation<GitAuthPromptResult, Never>?
    @ObservationIgnored let gitCredentialStore = GitCredentialStore()

    // Zion Code state
    var repositoryFiles: [FileItem] = [] {
        didSet { rebuildFlatFileCache() }
    }
    var openedFiles: [FileItem] = []
    var activeFileID: String?
    var selectedFileIDs: Set<String> = []
    @ObservationIgnored var lastClickedFileID: String?
    var selectedCodeFile: FileItem?
    var codeFileContent: String = "" {
        didSet { markCurrentFileUnsavedIfChanged() }
    }
    var editorFindSeedQuery: String = ""
    var editorFindSeedRequestID: Int = 0
    var expandedPaths: Set<String> = []
    var findInFilesScopeRequest: String? = nil

    // Tracking unsaved changes per file
    var unsavedFiles: Set<String> = []
    @ObservationIgnored var originalFileContents: [String: String] = [:]
    @ObservationIgnored var untitledCounter: Int = 0

    // File browser clipboard (cut/copy/paste)
    @ObservationIgnored var fileBrowserClipboard: (urls: [URL], isCut: Bool)?

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
    var editorLineSpacing: Double = 4.0 {
        didSet { UserDefaults.standard.set(editorLineSpacing, forKey: "editor.lineSpacing") }
    }
    var isLineWrappingEnabled: Bool = true {
        didSet { UserDefaults.standard.set(isLineWrappingEnabled, forKey: "editor.lineWrap") }
    }
    var editorTabSize: Int = 4 {
        didSet { UserDefaults.standard.set(editorTabSize, forKey: "editor.tabSize") }
    }
    var editorUseTabs: Bool = false {
        didSet { UserDefaults.standard.set(editorUseTabs, forKey: "editor.useTabs") }
    }
    var editorShowRuler: Bool = false {
        didSet { UserDefaults.standard.set(editorShowRuler, forKey: "editor.showRuler") }
    }
    var editorRulerColumn: Int = 80 {
        didSet { UserDefaults.standard.set(editorRulerColumn, forKey: "editor.rulerColumn") }
    }
    var editorAutoCloseBrackets: Bool = true {
        didSet { UserDefaults.standard.set(editorAutoCloseBrackets, forKey: "editor.autoCloseBrackets") }
    }
    var editorAutoCloseQuotes: Bool = true {
        didSet { UserDefaults.standard.set(editorAutoCloseQuotes, forKey: "editor.autoCloseQuotes") }
    }
    var editorLetterSpacing: Double = 0.0 {
        didSet { UserDefaults.standard.set(editorLetterSpacing, forKey: "editor.letterSpacing") }
    }
    var editorHighlightCurrentLine: Bool = true {
        didSet { UserDefaults.standard.set(editorHighlightCurrentLine, forKey: "editor.highlightCurrentLine") }
    }
    var editorBracketPairHighlight: Bool = true {
        didSet { UserDefaults.standard.set(editorBracketPairHighlight, forKey: "editor.bracketPairHighlight") }
    }
    var editorShowIndentGuides: Bool = false {
        didSet { UserDefaults.standard.set(editorShowIndentGuides, forKey: "editor.showIndentGuides") }
    }

    // Formatting settings
    var editorFormatOnSave: Bool = false {
        didSet { UserDefaults.standard.set(editorFormatOnSave, forKey: "editor.formatOnSave") }
    }
    var editorJsonSortKeys: Bool = false {
        didSet { UserDefaults.standard.set(editorJsonSortKeys, forKey: "editor.jsonSortKeys") }
    }

    // Terminal font settings
    var terminalFontSize: Double = 13.0 {
        didSet { UserDefaults.standard.set(terminalFontSize, forKey: "terminal.fontSize") }
    }
    var terminalFontFamily: String = "SF Mono" {
        didSet { UserDefaults.standard.set(terminalFontFamily, forKey: "terminal.fontFamily") }
    }
    var isTerminalFontAvailable: Bool {
        MonospaceFontResolver.isAvailable(name: terminalFontFamily)
    }

    var terminalOpacity: Double = 0.92 {
        didSet { UserDefaults.standard.set(terminalOpacity, forKey: "terminal.opacity") }
    }

    var showDotfiles: Bool = true {
        didSet {
            UserDefaults.standard.set(showDotfiles, forKey: "fileBrowser.showHiddenFiles")
            refreshFileTree()
        }
    }

    var branchInput: String = ""
    var tagInput: String = ""
    var tagMessage: String = ""
    var tagType: TagType = .lightweight
    var tagPushAfterCreate: Bool = false
    var isTagDetailSheetVisible: Bool = false
    var stashMessageInput: String = ""
    var cherryPickInput: String = ""
    var resetTargetInput: String = "HEAD~1"
    var rebaseTargetInput: String = ""
    var worktreePrefix: WorktreePrefix = .feat
    var worktreeNameInput: String = ""
    var isWorktreeAdvancedExpanded: Bool = false
    var worktreePathInput: String = ""
    var worktreeBranchInput: String = ""
    var remotes: [RemoteInfo] = []
    var remoteNameInput: String = "origin"
    var remoteURLInput: String = ""
    var commitMessageInput: String = ""
    var amendLastCommit: Bool = false
    var isTypingQuickly: Bool = false
    var shouldClosePopovers: Bool = false
    @ObservationIgnored let logger = DiagnosticLogger.shared

    var recentReposData: Data {
        get { UserDefaults.standard.data(forKey: "zion.recentRepositories") ?? Data() }
        set { UserDefaults.standard.set(newValue, forKey: "zion.recentRepositories") }
    }
    var recentRepositories: [URL] = []
    var recentWorktreeCounts: [URL: Int] = [:]

    // Performance caches
    private(set) var maxLaneCount: Int = 1
    var flatFileCache: [FileItem] = []
    var editorJumpLineTarget: Int = 0
    var editorJumpToken: Int = 0

    @ObservationIgnored let editorSymbolIndex = EditorSymbolIndex()
    @ObservationIgnored var editorSymbolIndexTask: Task<Void, Never>?

    var worktreeNameSlug: String {
        slugifiedWorktreeName(from: worktreeNameInput)
    }

    var derivedWorktreeBranch: String {
        guard !worktreeNameSlug.isEmpty else { return "" }
        return "\(worktreePrefix.rawValue)/\(worktreeNameSlug)"
    }

    var derivedWorktreePath: String {
        guard let repositoryURL, !worktreeNameSlug.isEmpty else { return "" }
        let parentDir = repositoryURL.deletingLastPathComponent()
        let repoName = repositoryURL.lastPathComponent
        let baseName = "\(repoName)-\(worktreePrefix.rawValue)-\(worktreeNameSlug)"
        return uniquePath(forBaseName: baseName, in: parentDir).path
    }

    var canSmartCreateWorktree: Bool {
        let manualPath = worktreePathInput.clean
        let manualBranch = worktreeBranchInput.clean
        if !manualPath.isEmpty, !manualBranch.isEmpty {
            return true
        }
        return !worktreeNameSlug.isEmpty
    }

    @ObservationIgnored private var repoEditorConfig: EditorConfig?
    var hasRepoEditorConfig: Bool { repoEditorConfig != nil }

    // Effective editor properties — repo config overrides global
    var effectiveTabSize: Int { repoEditorConfig?.tabSize ?? editorTabSize }
    var effectiveUseTabs: Bool { repoEditorConfig?.useTabs ?? editorUseTabs }
    var effectiveFontSize: Double { repoEditorConfig?.fontSize ?? editorFontSize }
    var effectiveRulerColumn: Int { repoEditorConfig?.rulerColumn ?? editorRulerColumn }
    var effectiveLineSpacing: Double { repoEditorConfig?.lineSpacing ?? editorLineSpacing }
    var effectiveShowRuler: Bool { repoEditorConfig?.showRuler ?? editorShowRuler }
    var effectiveShowIndentGuides: Bool { repoEditorConfig?.showIndentGuides ?? editorShowIndentGuides }
    var effectiveTheme: EditorTheme {
        if let name = repoEditorConfig?.theme, let t = EditorTheme(rawValue: name) { return t }
        return selectedTheme
    }

    @ObservationIgnored let git = GitClient()
    @ObservationIgnored let worker = RepositoryWorker()
    @ObservationIgnored let fileWatcher = FileWatcher()

    @ObservationIgnored let defaultCommitLimitAll = 700
    @ObservationIgnored let defaultCommitLimitFocused = 450
    @ObservationIgnored let commitPageSize = 300
    @ObservationIgnored let maxCommitLimit = 5000
    @ObservationIgnored var commitLimit = 700
    @ObservationIgnored var refreshRequestID = UUID()
    @ObservationIgnored var detailsRequestID = UUID()
    @ObservationIgnored var refreshTask: Task<Void, Never>?
    @ObservationIgnored var detailsTask: Task<Void, Never>?
    @ObservationIgnored var actionTask: Task<Void, Never>?
    @ObservationIgnored var pushPreflightTask: Task<Void, Never>?
    @ObservationIgnored var autoRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var deferredRepositoryLoadTask: Task<Void, Never>?
    @ObservationIgnored private var repositorySwitchToken = UUID()
    var isSwitchingRepository = false
    @ObservationIgnored private var cachedWorktreeStatusByPath: [String: (uncommittedCount: Int, hasConflicts: Bool)] = [:]
    @ObservationIgnored var cachedIgnoredPaths: Set<String>?
    var isRepositorySwitching: Bool { isSwitchingRepository }

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
            refreshPRReviewQueue()
            loadSubmodules()
            return
        }

        let switchToken = UUID()
        repositorySwitchToken = switchToken
        isSwitchingRepository = true
        logger.log(.info, "switch.start", context: "target=\(url.lastPathComponent) token=\(switchToken.uuidString.prefix(8))", source: #function)
        cancelRepositoryBackgroundActivityForSwitch()
        lastNotifiedBehindCount = 0

        repositoryURL = url
        repoEditorConfig = EditorConfig.load(from: url)
        saveRecentRepository(url)
        commitLimit = defaultCommitLimit(for: nil)
        worktreeNameInput = ""
        worktreePathInput = ""
        worktreeBranchInput = ""
        isWorktreeAdvancedExpanded = false

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
            backgroundRepoChangedFiles[previousURL] = uncommittedCount
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
        selectedChangeFile = nil
        currentFileDiff = ""
        currentFileDiffHunks = []
        selectedCommitFile = nil
        currentCommitFileDiff = ""
        currentCommitFileDiffHunks = []
        selectedHunkLines = []

        refreshRepository(
            setBusy: true,
            options: .critical,
            origin: .repositorySwitch,
            clearRepositorySwitchStateOnBusyCompletion: false
        )
        refreshFileTree()
        startFileWatcher(for: url)
        scheduleDeferredRepositoryLoads(for: url, switchToken: switchToken)

        if !pendingExternalFiles.isEmpty {
            let pending = pendingExternalFiles
            pendingExternalFiles = []
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                openFilesAsTabs(pending)
            }
        }
    }

    private func cancelRepositoryBackgroundActivityForSwitch() {
        deferredRepositoryLoadTask?.cancel()
        refreshTask?.cancel()
        prTask?.cancel()
        prPollingTask?.cancel()
        prPollingTimer?.cancel()
        backgroundFetchTask?.cancel()
        autoRefreshTask?.cancel()
    }

    private func scheduleDeferredRepositoryLoads(for url: URL, switchToken: UUID) {
        deferredRepositoryLoadTask?.cancel()
        deferredRepositoryLoadTask = Task { [weak self] in
            guard let self else { return }

            try? await Task.sleep(nanoseconds: Constants.Timing.repositorySwitchDeferral)
            guard !Task.isCancelled else { return }
            guard self.repositorySwitchToken == switchToken, self.repositoryURL == url else { return }

            for _ in 0..<Constants.Timing.maxRepositorySwitchAttempts {
                if Task.isCancelled { return }
                if !self.isBusy { break }
                try? await Task.sleep(nanoseconds: Constants.Timing.repositorySwitchPollInterval)
                guard self.repositorySwitchToken == switchToken, self.repositoryURL == url else { return }
            }

            guard !Task.isCancelled else { return }
            guard self.repositorySwitchToken == switchToken, self.repositoryURL == url else { return }

            self.logger.log(.info, "switch.deferred.begin", context: "repo=\(url.lastPathComponent) token=\(switchToken.uuidString.prefix(8))", source: #function)
            self.refreshRepository(
                setBusy: false,
                options: .full,
                origin: .repositorySwitch,
                onFinish: { [weak self] in
                    guard let self else { return }
                    guard self.repositorySwitchToken == switchToken, self.repositoryURL == url else { return }
                    self.loadPullRequests()
                    self.refreshPRReviewQueue()
                    self.startPRPollingTimer()
                    self.loadSubmodules()
                    self.loadSignatureStatuses()
                    self.startBackgroundFetch()
                    self.startAutoRefreshTimer()
                    self.isSwitchingRepository = false
                }
            )
        }
    }

    func mergeWorktreeStatusIfNeeded(_ incoming: [WorktreeItem], includeWorktreeStatus: Bool) -> [WorktreeItem] {
        if includeWorktreeStatus {
            for worktree in incoming {
                cachedWorktreeStatusByPath[worktree.path] = (
                    uncommittedCount: worktree.uncommittedCount,
                    hasConflicts: worktree.hasConflicts
                )
            }
            return incoming
        }

        return incoming.map { item in
            guard let cached = cachedWorktreeStatusByPath[item.path] else { return item }
            return WorktreeItem(
                path: item.path,
                head: item.head,
                branch: item.branch,
                isMainWorktree: item.isMainWorktree,
                isDetached: item.isDetached,
                isLocked: item.isLocked,
                lockReason: item.lockReason,
                isPrunable: item.isPrunable,
                pruneReason: item.pruneReason,
                isCurrent: item.isCurrent,
                uncommittedCount: cached.uncommittedCount,
                hasConflicts: cached.hasConflicts
            )
        }
    }

    var aiPendingChangesSummary: String = ""
    var isLoadingPendingChangesSummary: Bool = false
    @ObservationIgnored var pendingSummaryTask: Task<Void, Never>?

    func clearError() {
        lastError = nil
    }

    func friendlyErrorMessage(for error: Error) -> String? {
        guard case let GitClientError.commandFailed(command, message) = error else {
            return nil
        }

        guard command.contains("git checkout") else { return nil }

        let pattern = "'([^']+)' is already used by worktree at '([^']+)'"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
              let branchRange = Range(match.range(at: 1), in: message),
              let pathRange = Range(match.range(at: 2), in: message) else {
            return nil
        }

        let branch = String(message[branchRange])
        let path = String(message[pathRange])
        return L10n("gitError.checkout.usedByWorktree", branch, path)
    }

    func handleError(_ error: Error, source: String = #function) {
        let rawMessage = error.localizedDescription
        let message = friendlyErrorMessage(for: error)
            ?? ErrorClassifier.classify(rawMessage)
            ?? rawMessage
        lastError = message
        statusMessage = message
        logger.log(.error, rawMessage, source: source)
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
            guard let self else { return }
            guard !self.isSwitchingRepository else { return }
            self.refreshRepository(setBusy: false, origin: .fileWatcher)
            self.refreshFileTree()
        }
        fileWatcher.watch(directory: url)
    }

    @ObservationIgnored var prPollingTimer: Task<Void, Never>?

    deinit {
        deferredRepositoryLoadTask?.cancel()
        autoRefreshTask?.cancel()
        prPollingTimer?.cancel()
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

