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
        case gitAction
        case autoTimer
        case fileWatcher
        case repositorySwitch

        var usesSilentCommitDetails: Bool {
            switch self {
            case .autoTimer, .fileWatcher, .repositorySwitch:
                return true
            case .userInitiated, .gitAction:
                return false
            }
        }
    }

    enum CommitDetailsLoadPolicy {
        case interactive
        case silent
    }

    var repositoryURL: URL?
    var currentBranch: String = "-" {
        didSet {
            guard currentBranch != oldValue else { return }
            scheduleRepoMemoryRefreshIfNeeded()
        }
    }
    var headShortHash: String = "-" {
        didSet {
            guard headShortHash != oldValue else { return }
            scheduleRepoMemoryRefreshIfNeeded()
        }
    }
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
    var isBranchFocusLoading: Bool = false
    var branchFocusLoadingBranch: String?
    var inferBranchOrigins: Bool = true
    var hasMoreCommits: Bool = false
    var tags: [String] = []

    var latestReleaseTag: String? {
        tags.first
    }
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
    var currentFileDiff: String = "" {
        didSet {
            currentFileDiffLines = currentFileDiff
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
        }
    }
    var currentFileDiffLines: [String] = []
    var selectedCommitFile: String?
    var currentCommitFileDiff: String = ""
    var currentCommitFileDiffHunks: [DiffHunk] = []
    var isLoadingCommitDetails: Bool = false
    var isLoadingCommitFileDiff: Bool = false

    // Terminal — pane tree architecture
    var terminalTabs: [TerminalPaneNode] = []
    var activeTabID: UUID?
    var focusedSessionID: UUID?
    @ObservationIgnored lazy var terminalOutputCoordinator: TerminalOutputCoordinator = {
        let c = TerminalOutputCoordinator()
        c.viewModel = self
        return c
    }()

    /// Flat list of all sessions across all tabs (backward compat + tab bar)
    var terminalSessions: [TerminalSession] {
        terminalTabs.flatMap { $0.allSessions() }
    }
    /// Points to the focused session within the active tab
    var activeTerminalID: UUID? {
        get { focusedSessionID }
        set { focusedSessionID = newValue }
    }

    // Zen mode
    @ObservationIgnored var isZenModePaused = false
    @ObservationIgnored var zenResumeTask: Task<Void, Never>?

    // Clipboard
    @ObservationIgnored let clipboardMonitor = ClipboardMonitor()
    @ObservationIgnored var _isReloadingExpandedDirs = false
    @ObservationIgnored var terminalSendCallbacks: [UUID: (Data) -> Void] = [:]

    // Avatar cache (Gravatar)
    @ObservationIgnored let avatarCache = NSCache<NSString, NSImage>()
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

    // Git Bisect state
    var bisectPhase: BisectPhase = .inactive
    var bisectGoodCommits: Set<String> = []
    var bisectBadCommits: Set<String> = []
    var bisectCurrentHash: String = ""
    var bisectAIExplanation: String = ""
    var isBisectAILoading: Bool = false
    @ObservationIgnored var bisectTask: Task<Void, Never>?

    var isBisectActive: Bool { bisectPhase != .inactive }

    // Navigation signals (consumed by ContentView to switch tabs)
    var navigateToGraphRequested: Bool = false
    var navigateToCodeRequested: Bool = false
    var nextSectionAfterRepositoryOpen: AppSection?
    var pendingExternalFiles: [URL] = []

    // Bridge
    var bridgeState: BridgeProjectState = .empty
    var bridgeSourceTarget: BridgeTarget = .codex
    var bridgeDestinationTarget: BridgeTarget = .claude
    var bridgeAnalysis: BridgeMigrationAnalysis?
    var selectedBridgeRowID: String?
    var selectedBridgeRowIDs: Set<String> = []
    var isBridgeVisible: Bool = false
    var isBridgeLoading: Bool = false
    var isBridgeApplying: Bool = false
    @ObservationIgnored let bridgeService = BridgeService()
    @ObservationIgnored var bridgeAnalysisTask: Task<Void, Never>?

    // Git Hosting Provider integration
    var pullRequests: [HostedPRInfo] = []
    var isPRSheetVisible: Bool = false
    @ObservationIgnored let githubClient = GitHubClient()
    @ObservationIgnored let gitlabClient = GitLabClient()
    @ObservationIgnored let bitbucketClient = BitbucketClient()
    @ObservationIgnored let azureDevOpsClient = AzureDevOpsClient()
    @ObservationIgnored var hostingProvider: (any GitHostingProvider)?
    @ObservationIgnored let ntfyClient = NtfyClient()
    @ObservationIgnored var prTask: Task<Void, Never>?
    @ObservationIgnored var pullRequestLoadToken = UUID()
    @ObservationIgnored var observedOpenPRIDs: Set<Int>?
    @ObservationIgnored var previousPRTitles: [Int: String] = [:]

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
    var codeReviewProgressCurrent: Int = 0
    var codeReviewProgressTotal: Int = 0
    var codeReviewProgressFileName: String = ""
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

    // Submodule state
    var submodules: [SubmoduleInfo] = []
    @ObservationIgnored var submoduleTask: Task<Void, Never>?
    @ObservationIgnored var submoduleLoadToken = UUID()

    // AI commit message
    var suggestedCommitMessage: String = ""
    var isGeneratingAIMessage: Bool = false
    var aiQuotaExceeded: Bool = false
    var aiDiffExplanation: String = ""

    // AI Smart Services
    var aiConflictResolution: String = ""
    var aiConflictResolutionRegionID: UUID?
    var aiConflictResolvingRegionID: UUID?
    var aiReviewFindings: [ReviewFinding] = []
    var isReviewVisible: Bool = false
    @ObservationIgnored var commitDetailsCache = LRUCache<String, String>(capacity: Constants.Limits.commitDetailsCacheSize)
    @ObservationIgnored var commitFileDiffCache = LRUCache<String, (raw: String, hunks: [DiffHunk])>(capacity: Constants.Limits.commitFileDiffCacheSize)
    @ObservationIgnored var commitReviewCache: [String: [ReviewFinding]] = [:]
    var reviewingCommitID: String?
    var selectedCommitDetailTab: CommitDetailTab = .details
    var aiChangelog: String = ""
    var isChangelogSheetVisible: Bool = false
    var changelogFromRef: String = ""
    var changelogToRef: String = "HEAD"
    var aiHistorySearchError: String?
    var aiHistorySearchResult: AIHistorySearchResult?
    var isSemanticSearchActive: Bool = false

    // Full history search
    var gitSearchResults: [GitSearchResult] = []
    var isGitSearching: Bool = false
    var gitSearchQuery: String = ""
    @ObservationIgnored var gitSearchTask: Task<Void, Never>?

    var branchSummaries: [String: String] = [:]
    var aiBlameExplanation: String = ""
    var aiBlameEntryID: UUID?
    var aiCommitSplitSuggestions: [CommitSuggestion] = []
    var isSplitVisible: Bool = false
    var repoMemorySnapshot: RepoMemorySnapshot?
    var isRepoMemoryRefreshing: Bool = false
    var repoMemoryLastRefreshedAt: Date?
    var repoMemoryStatusMessage: String = ""

    // Pre-Commit AI Review Gate
    var preCommitReviewEnabled: Bool = false {
        didSet { UserDefaults.standard.set(preCommitReviewEnabled, forKey: UserDefaultsKeys.AI.preCommitReview) }
    }
    var aiTransferSupportHintsEnabled: Bool = true {
        didSet { UserDefaults.standard.set(aiTransferSupportHintsEnabled, forKey: UserDefaultsKeys.AI.transferSupportHints) }
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
            UserDefaults.standard.set(aiProvider.rawValue, forKey: UserDefaultsKeys.AI.provider)
            aiQuotaExceeded = false // Reset on provider change
            _aiKeyRevision += 1 // Ensure aiAPIKey getter is re-evaluated for the new provider
        }
    }
    var aiMode: AIMode = .efficient {
        didSet { UserDefaults.standard.set(aiMode.rawValue, forKey: UserDefaultsKeys.AI.mode) }
    }
    var commitMessageStyle: CommitMessageStyle = .compact {
        didSet { UserDefaults.standard.set(commitMessageStyle.rawValue, forKey: UserDefaultsKeys.AI.commitMessageStyle) }
    }
    @ObservationIgnored let aiClient = AIClient()
    @ObservationIgnored let aiSemaphore = AsyncSemaphore(maxConcurrent: 2)
    @ObservationIgnored let repoMemoryService = RepoMemoryService()
    @ObservationIgnored var aiTask: Task<Void, Never>?
    @ObservationIgnored var repoMemoryTask: Task<Void, Never>?

    @ObservationIgnored var _cachedAIKey: String?
    @ObservationIgnored var _cachedAIKeyProvider: AIProvider?
    var _aiKeyRevision: Int = 0

    // Commit signing
    var commitSignatureStatus: [String: String] = [:] // hash -> "G"/"N"/"B"/etc
    @ObservationIgnored var signatureStatusTask: Task<Void, Never>?
    @ObservationIgnored var signatureStatusLoadToken = UUID()

    // Background fetch
    var behindRemoteCount: Int = 0
    var aheadRemoteCount: Int = 0
    var showPushDivergenceWarning: Bool = false
    var pushDivergenceState: PushDivergenceState = .clear
    var divergenceResolution: DivergenceContext?
    @ObservationIgnored var busyWatchdogTask: Task<Void, Never>?
    @ObservationIgnored var backgroundFetchTask: Task<Void, Never>?
    @ObservationIgnored var lastNotifiedBehindCount: Int = 0
    @ObservationIgnored var notifiedReviewRequestPRIDs: Set<Int> = []
    @ObservationIgnored var autoFetchCredentialFailures: Int = 0
    @ObservationIgnored var autoFetchSuspendedUntil: Date?

    // ntfy Push Notifications
    var ntfyTopic: String = "" {
        didSet {
            UserDefaults.standard.set(ntfyTopic, forKey: UserDefaultsKeys.Ntfy.topic)
        }
    }
    var ntfyServerURL: String = "https://ntfy.sh" {
        didSet {
            UserDefaults.standard.set(ntfyServerURL, forKey: UserDefaultsKeys.Ntfy.serverURL)
        }
    }
    var ntfyEnabledEvents: [String] = NtfyEvent.defaultEnabledEvents {
        didSet { UserDefaults.standard.set(ntfyEnabledEvents, forKey: UserDefaultsKeys.Ntfy.enabledEvents) }
    }

    var ntfyEnabled: Bool = false {
        didSet { UserDefaults.standard.set(ntfyEnabled, forKey: UserDefaultsKeys.Ntfy.enabled) }
    }

    var ntfyLocalNotificationsEnabled: Bool = false {
        didSet { UserDefaults.standard.set(ntfyLocalNotificationsEnabled, forKey: UserDefaultsKeys.Ntfy.localNotifications) }
    }
    var prPollingIntervalMinutes: Int = 5 {
        didSet { UserDefaults.standard.set(prPollingIntervalMinutes, forKey: UserDefaultsKeys.Notifications.prPollingInterval) }
    }

    var isNtfyConfigured: Bool { ntfyEnabled && !ntfyTopic.isEmpty }

    // Mobile Remote Access
    var isMobileAccessEnabled: Bool = false {
        didSet { UserDefaults.standard.set(isMobileAccessEnabled, forKey: UserDefaultsKeys.MobileAccess.enabled) }
    }
    var mobileAccessConnectionState: RemoteAccessConnectionState = .disabled
    var mobileAccessLanQRImage: NSImage?
    var mobileAccessLanURL: String = ""
    var mobileAccessTunnelQRImage: NSImage?
    var mobileAccessTunnelURL: String = ""
    var isTunnelReady: Bool = false
    var pairedDevices: [PairedDevice] = []
    @ObservationIgnored var remoteAccessServer: RemoteAccessServer?
    @ObservationIgnored var tunnelManager: CloudflareTunnelManager?
    @ObservationIgnored var terminalOutputBuffers: [UUID: Data] = [:]
    @ObservationIgnored var terminalLastSentRows: [UUID: [String]] = [:]
    @ObservationIgnored var screenUpdateDebounceTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored var screenUpdateThrottleDeadlines: [UUID: ContinuousClock.Instant] = [:]
    @ObservationIgnored var heartbeatTask: Task<Void, Never>?
    @ObservationIgnored var hasEnsuredRemoteTerminals = false
    @ObservationIgnored var sleepAssertionID: IOPMAssertionID = 0
    @ObservationIgnored var sleepTimerTask: Task<Void, Never>?
    var keepAwakeExpiresAt: Date?
    var isPreventingSleep = false
    var keepAwakeWarning15Sent = false
    var keepAwakeWarning5Sent = false
    @ObservationIgnored var wakeObserver: NSObjectProtocol?
    @ObservationIgnored var activeGitActionToken: UUID?

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
        didSet { isFlatFileCacheDirty = true }
    }
    var openedFiles: [FileItem] = []
    var missingOpenFileIDs: Set<String> = []
    var activeFileID: String?
    var selectedFileIDs: Set<String> = []
    @ObservationIgnored var lastClickedFileID: String?
    var selectedCodeFile: FileItem?
    var codeFileContent: String = "" {
        didSet {
            guard !isApplyingEditorContent else { return }
            syncActiveDraftFromEditorContent()
        }
    }
    var editorFindSeedQuery: String = ""
    var editorFindSeedRequestID: Int = 0
    var editorFocusRequestID: Int = 0
    var expandedPaths: Set<String> = []
    var findInFilesScopeRequest: String? = nil

    // Tracking unsaved changes per file
    var unsavedFiles: Set<String> = []
    @ObservationIgnored var originalFileContents: [String: String] = [:]
    @ObservationIgnored var draftFileContents: [String: String] = [:]
    @ObservationIgnored var isApplyingEditorContent: Bool = false
    @ObservationIgnored var dirtyFileCloseDecisionHandler: ((FileItem) -> EditorDirtyCloseDecision)? = nil
    @ObservationIgnored var untitledCounter: Int = 0

    // File browser clipboard (cut/copy/paste)
    @ObservationIgnored var fileBrowserClipboard: (urls: [URL], isCut: Bool)?

    // Editor Settings (persisted via UserDefaults)
    var selectedTheme: EditorTheme = .dracula {
        didSet { UserDefaults.standard.set(selectedTheme.rawValue, forKey: UserDefaultsKeys.Editor.theme) }
    }
    var editorFontSize: Double = 13.0 {
        didSet { UserDefaults.standard.set(editorFontSize, forKey: UserDefaultsKeys.Editor.fontSize) }
    }
    var editorFontFamily: String = "SF Mono" {
        didSet { UserDefaults.standard.set(editorFontFamily, forKey: UserDefaultsKeys.Editor.fontFamily) }
    }
    var editorLineSpacing: Double = 4.0 {
        didSet { UserDefaults.standard.set(editorLineSpacing, forKey: UserDefaultsKeys.Editor.lineSpacing) }
    }
    var isLineWrappingEnabled: Bool = true {
        didSet { UserDefaults.standard.set(isLineWrappingEnabled, forKey: UserDefaultsKeys.Editor.lineWrap) }
    }
    var editorTabSize: Int = 4 {
        didSet { UserDefaults.standard.set(editorTabSize, forKey: UserDefaultsKeys.Editor.tabSize) }
    }
    var editorUseTabs: Bool = false {
        didSet { UserDefaults.standard.set(editorUseTabs, forKey: UserDefaultsKeys.Editor.useTabs) }
    }
    var editorShowRuler: Bool = false {
        didSet { UserDefaults.standard.set(editorShowRuler, forKey: UserDefaultsKeys.Editor.showRuler) }
    }
    var editorRulerColumn: Int = 80 {
        didSet { UserDefaults.standard.set(editorRulerColumn, forKey: UserDefaultsKeys.Editor.rulerColumn) }
    }
    var editorAutoCloseBrackets: Bool = true {
        didSet { UserDefaults.standard.set(editorAutoCloseBrackets, forKey: UserDefaultsKeys.Editor.autoCloseBrackets) }
    }
    var editorAutoCloseQuotes: Bool = true {
        didSet { UserDefaults.standard.set(editorAutoCloseQuotes, forKey: UserDefaultsKeys.Editor.autoCloseQuotes) }
    }
    var editorLetterSpacing: Double = 0.0 {
        didSet { UserDefaults.standard.set(editorLetterSpacing, forKey: UserDefaultsKeys.Editor.letterSpacing) }
    }
    var editorHighlightCurrentLine: Bool = true {
        didSet { UserDefaults.standard.set(editorHighlightCurrentLine, forKey: UserDefaultsKeys.Editor.highlightCurrentLine) }
    }
    var editorBracketPairHighlight: Bool = true {
        didSet { UserDefaults.standard.set(editorBracketPairHighlight, forKey: UserDefaultsKeys.Editor.bracketPairHighlight) }
    }
    var editorShowIndentGuides: Bool = false {
        didSet { UserDefaults.standard.set(editorShowIndentGuides, forKey: UserDefaultsKeys.Editor.showIndentGuides) }
    }

    // Formatting settings
    var editorFormatOnSave: Bool = false {
        didSet { UserDefaults.standard.set(editorFormatOnSave, forKey: UserDefaultsKeys.Editor.formatOnSave) }
    }
    var editorJsonSortKeys: Bool = false {
        didSet { UserDefaults.standard.set(editorJsonSortKeys, forKey: UserDefaultsKeys.Editor.jsonSortKeys) }
    }

    // Terminal font settings
    var terminalFontSize: Double = 13.0 {
        didSet { UserDefaults.standard.set(terminalFontSize, forKey: UserDefaultsKeys.Terminal.fontSize) }
    }
    var terminalFontFamily: String = "SF Mono" {
        didSet { UserDefaults.standard.set(terminalFontFamily, forKey: UserDefaultsKeys.Terminal.fontFamily) }
    }

    var terminalOpacity: Double = 0.92 {
        didSet { UserDefaults.standard.set(terminalOpacity, forKey: UserDefaultsKeys.Terminal.opacity) }
    }

    var showDotfiles: Bool = true {
        didSet {
            UserDefaults.standard.set(showDotfiles, forKey: UserDefaultsKeys.FileBrowser.showHiddenFiles)
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
        get { UserDefaults.standard.data(forKey: UserDefaultsKeys.General.recentRepositories) ?? Data() }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.General.recentRepositories) }
    }
    var recentRepositories: [URL] = []
    var recentWorktreeCounts: [URL: Int] = [:]

    // Performance caches
    var maxLaneCount: Int = 1
    var flatFileCache: [FileItem] = []
    @ObservationIgnored var isFlatFileCacheDirty: Bool = true
    var editorJumpLineTarget: Int = 0
    var editorJumpToken: Int = 0
    @ObservationIgnored var repositorySwitchSnapshots: [URL: RepositorySwitchSnapshot] = [:]
    @ObservationIgnored var expandedPathsByRepository: [URL: Set<String>] = [:]
    @ObservationIgnored var ignoredPathsCacheByRepository: [URL: IgnoredPathsCacheEntry] = [:]
    @ObservationIgnored let repositorySwitchSnapshotTTL: TimeInterval = 5
    @ObservationIgnored let ignoredPathsCacheTTL: TimeInterval = 10

    @ObservationIgnored let editorSymbolIndex = EditorSymbolIndex()
    @ObservationIgnored var editorSymbolIndexTask: Task<Void, Never>?
    @ObservationIgnored var lastSymbolIndexRebuildAt: Date?
    @ObservationIgnored var symbolIndexRebuildRepositoryURL: URL?
    @ObservationIgnored var fileTreeRefreshTask: Task<Void, Never>?
    @ObservationIgnored var fileTreeRefreshRequestID = UUID()

    @ObservationIgnored var repoEditorConfig: EditorConfig?
    var hasRepoEditorConfig: Bool { repoEditorConfig != nil }

    // Per-file detected indentation (overrides repo config and global setting)
    var fileDetectedTabSize: Int?
    var fileDetectedUseTabs: Bool?

    @ObservationIgnored let git = GitClient()
    @ObservationIgnored let worker = RepositoryWorker()
    @ObservationIgnored let fileWatcher = FileWatcher()

    @ObservationIgnored let defaultCommitLimitAll = 300
    @ObservationIgnored let defaultCommitLimitFocused = 200
    @ObservationIgnored let commitPageSize = 300
    @ObservationIgnored let maxCommitLimit = 5000
    @ObservationIgnored var commitLimit = 300
    @ObservationIgnored var refreshRequestID = UUID()
    @ObservationIgnored var detailsRequestID = UUID()
    @ObservationIgnored var refreshTask: Task<Void, Never>?
    @ObservationIgnored var detailsTask: Task<Void, Never>?
    @ObservationIgnored var actionTask: Task<Void, Never>?
    @ObservationIgnored var pushPreflightTask: Task<Void, Never>?
    @ObservationIgnored var autoRefreshTask: Task<Void, Never>?
    @ObservationIgnored var deferredRepositoryLoadTask: Task<Void, Never>?
    @ObservationIgnored var repositorySwitchToken = UUID()
    @ObservationIgnored var pendingFileWatcherEvent: FileWatcher.ChangeEvent?
    @ObservationIgnored var isApplyingFileWatcherRefresh = false
    @ObservationIgnored var fileWatcherGateTask: Task<Void, Never>?
    @ObservationIgnored var suppressFileWatcherGitMetadataUntil: Date = .distantPast
    var pendingRepositoryURL: URL?
    var isSwitchingRepository = false
    var isBlockingRepositorySwitch = false
    @ObservationIgnored var cachedWorktreeStatusByPath: [String: (uncommittedCount: Int, hasConflicts: Bool)] = [:]
    @ObservationIgnored var cachedIgnoredPaths: Set<String>?
    var isRepositorySwitching: Bool { isSwitchingRepository }
    var isRepositorySwitchBlocking: Bool { isSwitchingRepository && isBlockingRepositorySwitch }
    var isRepositorySwitchRefreshingInBackground: Bool {
        isSwitchingRepository && !isBlockingRepositorySwitch
    }

    var aiPendingChangesSummary: String = ""
    var isLoadingPendingChangesSummary: Bool = false
    @ObservationIgnored var pendingSummaryTask: Task<Void, Never>?

    @ObservationIgnored var prPollingTimer: Task<Void, Never>?

    deinit {
        deferredRepositoryLoadTask?.cancel()
        autoRefreshTask?.cancel()
        prPollingTimer?.cancel()
        fileWatcherGateTask?.cancel()
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
