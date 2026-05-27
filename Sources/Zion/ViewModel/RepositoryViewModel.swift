import AppKit
import Foundation
import SwiftUI
import CryptoKit
import UniformTypeIdentifiers
import IOKit.pwr_mgt
@preconcurrency import SwiftTerm

@Observable @MainActor
final class RepositoryViewModel {
    final class WeakReference {
        weak var value: RepositoryViewModel?
    }

    struct ReplaceUndoEntry {
        let targetContents: [String: String]
        let inverseContents: [String: String]
    }

    static let activeReference = WeakReference()

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
    var hasOpenWorkspace: Bool { repositoryURL != nil }
    var hasGitWorkspace: Bool { repositoryURL != nil && isGitRepository }

    func canAccess(_ section: AppSection) -> Bool {
        section == .code || hasOpenWorkspace
    }
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
    var commits: [Commit] = []
    var selectedCommitID: String?
    var commitDetails: String = "Selecione um commit para ver os detalhes."
    var branches: [String] = []
    var branchInfos: [BranchInfo] = []
    var mergedBranchesPreview: [String] = []
    var focusedBranch: String?
    var isBranchFocusLoading: Bool = false
    var branchFocusLoadingBranch: String?
    var hasMoreCommits: Bool = false
    var tags: [String] = []

    var latestReleaseTag: String? {
        tags.first
    }
    var stashes: [String] = []
    var selectedStash: String = ""

    func applyTagAndStashPayload(_ payload: RepositoryLoadPayload, includeTagsAndStashes: Bool) {
        guard includeTagsAndStashes else { return }
        tags = payload.tags
        stashes = payload.stashes
        selectedStash = payload.selectedStash
    }

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
    var uncommittedChanges: [String] = [] {
        didSet { rebuildUncommittedLookupSets() }
    }
    var uncommittedCount: Int = 0

    // Pre-computed sets for O(1) file tree lookups (PERF-005)
    @ObservationIgnored var uncommittedFilePaths: Set<String> = []
    @ObservationIgnored var uncommittedDirectoryPrefixes: Set<String> = []

    private func rebuildUncommittedLookupSets() {
        var paths = Set<String>()
        var dirs = Set<String>()
        for change in uncommittedChanges {
            // Porcelain lines have a 3-char status prefix: "XY path" (e.g. " M src/foo.txt")
            let filePath = change.count > 3 ? String(change.dropFirst(3)) : change
            // Handle renames: "R  old -> new" -- use the new path
            let resolvedPath: String
            if let arrowRange = filePath.range(of: " -> ") {
                resolvedPath = String(filePath[arrowRange.upperBound...])
            } else {
                resolvedPath = filePath
            }
            paths.insert(resolvedPath)
            if let lastSlash = resolvedPath.lastIndex(of: "/") {
                // Build directory prefixes: "src/foo/bar.txt" -> "src/foo/", "src/"
                var dirPath = resolvedPath[resolvedPath.startIndex..<lastSlash]
                while !dirPath.isEmpty {
                    dirs.insert(String(dirPath) + "/")
                    if let prevSlash = dirPath.lastIndex(of: "/") {
                        dirPath = dirPath[dirPath.startIndex..<prevSlash]
                    } else {
                        dirs.insert(String(dirPath) + "/")
                        break
                    }
                }
            }
        }
        uncommittedFilePaths = paths
        uncommittedDirectoryPrefixes = dirs
    }
    var selectedChangeFile: String?
    var currentFileDiff: String = "" {
        didSet {
            currentFileDiffLines = currentFileDiff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
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
    @ObservationIgnored let avatarCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 200
        cache.totalCostLimit = 10 * 1024 * 1024 // 10 MB
        return cache
    }()
    @ObservationIgnored var avatarDownloadTasks: Set<String> = []
    @ObservationIgnored let avatarSemaphore = AsyncSemaphore(maxConcurrent: 3)

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

    /// Current active section, synced from ContentView. Used for tab-aware loading:
    /// - .code: only load branch + status + file tree (editor + terminal)
    /// - .graph: load full commit graph, branches, tags, stashes
    /// - .operations: load uncommitted changes + branch info for git ops
    @ObservationIgnored var activeSection: AppSection = .code
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
    var prSheetTargetBranch: String?
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
    @ObservationIgnored var commitReviewCache = LRUCache<String, [ReviewFinding]>(capacity: 32)
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
    @ObservationIgnored var repoMemoryLastRefreshedAt: Date?
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
    @ObservationIgnored var _aiKeyRevision: Int = 0

    // Commit signing
    @ObservationIgnored var commitSignatureStatus: [String: String] = [:] // hash -> "G"/"N"/"B"/etc
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
    @ObservationIgnored var isBackgroundFetching = false
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
    var mobileAccessTunnelErrorMessage: String?
    var isTunnelReady: Bool = false
    var pairedDevices: [PairedDevice] = []
    @ObservationIgnored var remoteAccessServer: RemoteAccessServer?
    @ObservationIgnored var tunnelManager: CloudflareTunnelManager?
    @ObservationIgnored var remoteAccessStartupTask: Task<Void, Never>?
    @ObservationIgnored var remoteAccessTunnelTask: Task<Void, Never>?
    @ObservationIgnored var terminalOutputBuffers: [UUID: Data] = [:]
    @ObservationIgnored var promptContextBuffers: [UUID: [String]] = [:]
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
    var selectedCodeFile: FileItem? {
        didSet {
            // Wave 3: auto-reveal parent chain in the file tree when the active
            // editor file changes. No-op when disabled, nil, or outside the repo.
            revealSelectedCodeFileInTree()
        }
    }
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
    var revealFileInBrowserRequestID: Int = 0

    // Tracking unsaved changes per file
    var unsavedFiles: Set<String> = []
    @ObservationIgnored var originalFileContents: [String: String] = [:]
    @ObservationIgnored var draftFileContents: [String: String] = [:]
    @ObservationIgnored var isApplyingEditorContent: Bool = false
    @ObservationIgnored var replaceUndoStack: [ReplaceUndoEntry] = []
    @ObservationIgnored var replaceRedoStack: [ReplaceUndoEntry] = []
    @ObservationIgnored var dirtyFileCloseDecisionHandler: ((FileItem) -> EditorDirtyCloseDecision)? = nil
    @ObservationIgnored var untitledCounter: Int = 0

    var hasPendingWorkspaceReplaceUndo: Bool {
        !replaceUndoStack.isEmpty
    }

    var hasPendingWorkspaceReplaceRedo: Bool {
        !replaceRedoStack.isEmpty
    }

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
    var editorTrimTrailingWhitespace: Bool = false {
        didSet { UserDefaults.standard.set(editorTrimTrailingWhitespace, forKey: UserDefaultsKeys.Editor.trimTrailingWhitespace) }
    }
    var editorRenderWhitespace: String = "none" {
        didSet { UserDefaults.standard.set(editorRenderWhitespace, forKey: UserDefaultsKeys.Editor.renderWhitespace) }
    }
    var editorTopPadding: Double = 6.0 {
        didSet { UserDefaults.standard.set(editorTopPadding, forKey: UserDefaultsKeys.Editor.topPadding) }
    }
    var editorScrollPastEnd: Bool = true {
        didSet { UserDefaults.standard.set(editorScrollPastEnd, forKey: UserDefaultsKeys.Editor.scrollPastEnd) }
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
    @ObservationIgnored var isRepositoryDisposed: Bool = false
    @ObservationIgnored let operations = OperationManager()

    // IdleFocusGate (Wave 2) — defers file-watcher-driven refreshes while the app
    // window is backgrounded or a non-read-only operation is running.
    @ObservationIgnored var pendingFileWatcherRefresh: Bool = false
    @ObservationIgnored var didArmActivationObserver: Bool = false
    @ObservationIgnored var isActiveOverrideForTesting: Bool?
    @ObservationIgnored var refreshFireCountForTesting: Int = 0

    /// Tracks whether the full graph data (commits, branches, tags) has been loaded
    /// for the current repository. Reset on repo switch. When the user is on Code tab,
    /// we skip the heavy graph load and defer it until they navigate to Graph/Ops.
    @ObservationIgnored var hasLoadedFullGraphForCurrentRepo = false
    /// Set true whenever a Code-section file-watcher event runs the minimal
    /// refresh path (branch/head/status/conflicts only). Cleared on Tree/Ops
    /// section entry by triggering a background refresh that re-loads
    /// commits, branches, tags, stashes, and per-worktree enrichment.
    /// (RT-007)
    @ObservationIgnored var treeOpsDataStale: Bool = false

    var recentReposData: Data {
        get { UserDefaults.standard.data(forKey: UserDefaultsKeys.General.recentRepositories) ?? Data() }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.General.recentRepositories) }
    }
    var recentRepositories: [URL] = []
    var recentWorktreeCounts: [URL: Int] = [:]

    // Performance caches
    var maxLaneCount: Int = 1
    @ObservationIgnored var flatFileCache: [FileItem] = []
    @ObservationIgnored var isFlatFileCacheDirty: Bool = true
    var editorJumpLineTarget: Int = 0
    var editorJumpToken: Int = 0
    @ObservationIgnored var repositorySwitchSnapshots: [URL: RepositorySwitchSnapshot] = [:]
    @ObservationIgnored var expandedPathsByRepository: [URL: Set<String>] = [:]
    @ObservationIgnored var ignoredPathsCacheByRepository: [URL: IgnoredPathsCacheEntry] = [:]
    @ObservationIgnored let repositorySwitchSnapshotTTL: TimeInterval = 5
    @ObservationIgnored let ignoredPathsCacheTTL: TimeInterval = 10
    @ObservationIgnored let recentRepoPrefetcher = RecentRepositoryPrefetcher()
    @ObservationIgnored var recentRepoPrefetchTask: Task<Void, Never>?

    @ObservationIgnored let editorSymbolIndex = EditorSymbolIndex()
    @ObservationIgnored var editorSymbolIndexTask: Task<Void, Never>?
    @ObservationIgnored var lastSymbolIndexRebuildAt: Date?
    @ObservationIgnored var symbolIndexRebuildRepositoryURL: URL?
    @ObservationIgnored var fileTreeRefreshTask: Task<Void, Never>?
    @ObservationIgnored var fileTreeRefreshRequestID = UUID()
    @ObservationIgnored var isRefreshingFileTree = false
    @ObservationIgnored var pendingFileTreeRefreshForceReload = false
    @ObservationIgnored var pendingFileTreeRefreshRepositoryURL: URL?
    @ObservationIgnored var fileTreeRefreshOnFinish: (() -> Void)?

    @ObservationIgnored var repoEditorConfig: EditorConfig?
    var hasRepoEditorConfig: Bool { repoEditorConfig != nil }

    // Per-file detected indentation (overrides repo config and global setting)
    var fileDetectedTabSize: Int?
    var fileDetectedUseTabs: Bool?

    @ObservationIgnored let git = GitClient()
    @ObservationIgnored let worker = RepositoryWorker()
    @ObservationIgnored let fileWatcher = FileWatcher()
    @ObservationIgnored var _chatService: ChatService?
    @ObservationIgnored private(set) var chatStorage = ChatStorage()

    @ObservationIgnored let defaultCommitLimitAll = 100
    @ObservationIgnored let defaultCommitLimitFocused = 100
    @ObservationIgnored let commitPageSize = 200
    @ObservationIgnored let maxCommitLimit = 5000
    @ObservationIgnored var commitLimit = 300
    @ObservationIgnored var refreshRequestID = UUID()
    @ObservationIgnored var detailsRequestID = UUID()
    /// Timestamp of the last successful refresh; used to coalesce redundant
    /// background refreshes (autoTimer / fileWatcher) that fire within a few
    /// seconds of a completed load. User-initiated and operational refreshes
    /// (repositorySwitch, gitAction, userInitiated) bypass this coalescing.
    @ObservationIgnored var lastRefreshSucceededAt: Date?
    @ObservationIgnored var refreshTask: Task<Void, Never>?
    @ObservationIgnored var detailsTask: Task<Void, Never>?
    @ObservationIgnored var actionTask: Task<Void, Never>?
    @ObservationIgnored var pushPreflightTask: Task<Void, Never>?
    @ObservationIgnored var lastBehindRemoteCheckDate: Date = .distantPast
    @ObservationIgnored var deferredRepositoryLoadTask: Task<Void, Never>?
    @ObservationIgnored var repositorySwitchToken = UUID()
    @ObservationIgnored var pendingFileWatcherEvent: FileWatcher.ChangeEvent?
    @ObservationIgnored var isApplyingFileWatcherRefresh = false
    @ObservationIgnored var fileWatcherGateTask: Task<Void, Never>?
    @ObservationIgnored var suppressFileWatcherGitMetadataUntil: Date = .distantPast
    /// Set when a structural file-watcher event is suppressed because the user
    /// is on a non-Code section (Graph/Operations). Drained on switch back to
    /// `.code` via `replayPendingTreeRefreshIfNeeded()`. (RT-003)
    @ObservationIgnored var pendingFileTreeRefreshFromGate = false
    @ObservationIgnored var sectionReturnReplayTask: Task<Void, Never>?
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
        // Git & refresh tasks
        refreshTask?.cancel()
        detailsTask?.cancel()
        actionTask?.cancel()
        deferredRepositoryLoadTask?.cancel()
        fileWatcherGateTask?.cancel()
        sectionReturnReplayTask?.cancel()
        fileTreeRefreshTask?.cancel()
        commitStatsTask?.cancel()
        pushPreflightTask?.cancel()
        busyWatchdogTask?.cancel()

        // Background sync tasks
        backgroundFetchTask?.cancel()
        prPollingTimer?.cancel()
        prPollingTask?.cancel()
        prTask?.cancel()
        signatureStatusTask?.cancel()
        submoduleTask?.cancel()

        // AI tasks
        aiTask?.cancel()
        repoMemoryTask?.cancel()
        codeReviewTask?.cancel()
        explainDiffTask?.cancel()
        bisectTask?.cancel()
        pendingSummaryTask?.cancel()

        // Editor & history tasks
        blameTask?.cancel()
        reflogTask?.cancel()
        fileHistoryTask?.cancel()
        recoverySnapshotsTask?.cancel()
        gitSearchTask?.cancel()
        editorSymbolIndexTask?.cancel()
        bridgeAnalysisTask?.cancel()
        conflictTask?.cancel()
        cloneTask?.cancel()

        // Remote access tasks
        remoteAccessStartupTask?.cancel()
        remoteAccessTunnelTask?.cancel()
        heartbeatTask?.cancel()
        sleepTimerTask?.cancel()

        // Misc
        zenResumeTask?.cancel()

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
