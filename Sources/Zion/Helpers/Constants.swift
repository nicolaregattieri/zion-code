import AppKit
import Foundation

enum Constants {
    /// ASCII Unit Separator (0x1F) used as field delimiter in git format strings
    static let gitFieldSeparator = Character(UnicodeScalar(0x1F)!)
    /// ASCII Record Separator (0x1E) used as record delimiter in git format strings
    static let gitRecordSeparator = Character(UnicodeScalar(0x1E)!)

    // MARK: - Timing Control Center
    //
    // All timing constants in one place. Grouped by behavior so you can
    // see at a glance when each background system fires and how they
    // coordinate with each other.
    //
    // TAB-AWARE LOADING:
    //   Code tab:  branch + status + file tree only (3 git cmds, ~100ms)
    //   Graph tab: full commit graph + branches + tags + stashes (15+ cmds)
    //   Ops tab:   full refresh (needs branch info for operations)
    //   Switching tabs triggers deferred load if graph not yet loaded.
    //
    // STARTUP STAGGER (after repository switch finalization):
    //   +0s   Initial refresh (Code: lightweight, Graph/Ops: full)
    //   +30s  backgroundFetchInitialDelay -- first remote fetch
    //   +45s  behindRemoteCheckInitialDelay -- first behind-remote check
    //   +90s  prPollingInitialDelay -- first PR badge update
    //
    // STEADY STATE (recurring intervals, staggered to avoid overlap):
    //   On activate  behindRemoteCheck -- behind/ahead badge update (cooldown 60s)
    //   Every 300s  backgroundFetchInterval -- remote fetch (with ls-remote pre-check)
    //   Every 300s  prPollingInterval -- PR badge update
    //   Every 3.0s  clipboardPollInterval -- pasteboard changeCount check (utility queue)
    //
    // FILE WATCHER (event-driven, not polling):
    //   FSEvents latency: 0.5s (OS delivers events in batches)
    //   Debounce: 500ms (coalesce rapid changes before processing)
    //   Content change -> git status only (1 command, <1s feedback)
    //   Git metadata change -> full worktreeStatus refresh
    //
    // INACTIVE REPOS (background monitoring for change badges):
    //   Event-driven via FSEvents FileWatcher (no polling)

    enum Timing {

        // --- Background Sync (recurring) ---

        /// Minimum cooldown between behind-remote checks triggered by app activation.
        static let behindRemoteCheckCooldown: TimeInterval = 60

        /// How often Zion fetches from remote to update behind/ahead badges.
        /// Uses ls-remote pre-check to skip expensive fetch when remote is unchanged.
        static let backgroundFetchInterval: UInt64 = 300_000_000_000 // 5min

        /// How often Zion polls GitHub/GitLab/Bitbucket for new PRs and review requests.
        static let prPollingInterval: UInt64 = 5 * 60 * 1_000_000_000 // 5min

        /// How often the clipboard monitor checks NSPasteboard.changeCount.
        /// Cheap O(1) integer comparison; only does work when clipboard actually changed.
        /// 3s keeps copy-paste workflow responsive without wasting cycles.
        /// Timer runs on utility queue with 500ms leeway for OS coalescing.
        static let clipboardPollInterval: TimeInterval = 3.0

        // --- Startup Stagger (initial delays after repo switch) ---
        // These spread out the first tick of each timer to avoid a CPU spike.

        /// Delay before the first remote fetch after opening a repository.
        static let backgroundFetchInitialDelay: UInt64 = 30_000_000_000 // 30s

        /// Delay before the first behind-remote check after opening a repository.
        static let behindRemoteCheckInitialDelay: UInt64 = 45_000_000_000 // 45s

        /// Delay before the first PR poll after opening a repository.
        static let prPollingInitialDelay: UInt64 = 90_000_000_000 // 90s

        // --- File Watcher ---

        /// FSEvents latency: how long the OS batches file system events before delivering.
        /// 0.2s keeps single-file save feedback under ~400ms total while bulk writes
        /// still get coalesced via the path ceiling and `isFilteredNoisePath` classifier. (RT-005)
        static let fileWatcherLatency: TimeInterval = 0.2

        /// Debounce window after receiving file events before processing.
        /// Coalesces rapid changes (e.g., `npm install` writing 100 files) into one refresh.
        /// 200ms because the coalescer (100ms) already merges adjacent paths and FSEvents
        /// itself batches at the OS layer. (RT-005)
        static let fileWatcherDebounce: UInt64 = 200_000_000 // 200ms

        /// Coalescing window for the FileWatcher path deduplication layer.
        /// Incoming FSEvents paths are buffered into a Set of parent directories and flushed
        /// as a single ChangeEvent after this window elapses (or when the path ceiling is hit).
        static let fileWatcherCoalesceWindow: UInt64 = 100_000_000 // 100ms

        /// Grace period applied after the app regains focus before firing a deferred
        /// file-watcher-driven refresh. Prevents thrash on rapid activate/resign bursts.
        static let refreshRepositoryIdleGrace: UInt64 = 200_000_000 // 200ms

        // --- Inactive Repo Monitoring ---
        // Background repos are now purely event-driven via FSEvents FileWatcher.
        // No polling loop runs for inactive repos.

        // --- Repository Switch ---

        /// Delay before starting deferred loads after a repo switch.
        /// Gives the UI time to render the snapshot before heavy work begins.
        static let repositorySwitchDeferral: UInt64 = 250_000_000 // 250ms

        /// Polling interval while waiting for busy state to clear during repo switch.
        static let repositorySwitchPollInterval: UInt64 = 50_000_000 // 50ms

        /// Maximum polling attempts before giving up on busy state during switch.
        static let maxRepositorySwitchAttempts = 40 // 40 x 50ms = 2s max

        /// Safety timeout to force-clear isSwitchingRepository if finalization never fires.
        /// Cold OS-cache loads on a fresh repo open can exceed 10s; the watchdog must be a
        /// safety net, not the normal path.
        static let repositorySwitchWatchdogTimeout: UInt64 = 20_000_000_000 // 20s

        // --- Retry / Network Error ---

        /// Wait before retrying after a transient network error during background fetch.
        static let networkRetryDelay: UInt64 = 2_000_000_000 // 2s

        // --- Safety Watchdogs ---

        /// Safety timeout to force-clear isBusy if a refresh never completes.
        static let busyWatchdogTimeout: UInt64 = 60_000_000_000 // 60s

        /// Grace period before escalating SIGTERM to SIGKILL for frozen terminal processes.
        static let processKillEscalation: UInt64 = 500_000_000 // 500ms

        // --- UI Debounces ---

        /// Debounce before computing selection occurrence highlights in the editor.
        static let selectionOccurrenceDebounce: TimeInterval = 0.1 // 100ms

        /// Debounce before filtering the file browser tree after keystroke.
        static let fileBrowserFilterDebounce: TimeInterval = 0.15 // 150ms

        /// Delay before opening conflict resolver after transfer support detection.
        static let transferSupportDelay: UInt64 = 600_000_000 // 600ms

        // --- Zen Mode ---

        /// Delay between zen mode choreography steps (sidebar collapse, toolbar hide, etc.).
        static let zenModeStepDelay: TimeInterval = 0.25

        /// Delay before restoring layout after zen mode sidebar appears.
        static let zenModeRestoreDelay: TimeInterval = 0.5

        /// Debounce before restarting background tasks after exiting zen mode.
        /// 5s avoids accidental toggle flicker without leaving the user stale for too long.
        static let zenModeResumeDebounce: UInt64 = 5_000_000_000 // 5s

        // --- Search Debounces ---

        /// Debounce before executing commit search in the graph view.
        static let commitSearchDebounce: UInt64 = 150_000_000 // 150ms

        /// Debounce before executing find-in-files search.
        static let findInFilesSearchDebounce: UInt64 = 300_000_000 // 300ms

        // --- Terminal Rendering ---
        // Terminal output is batched to avoid starving the main thread.
        // Formula: min(maxFlush, baseFlush + (terminalCount - 1) * perTerminalFlush)

        /// Base flush interval for terminal output (single terminal). ~60fps.
        static let terminalFlushBaseInterval: UInt64 = 16_000_000 // 16ms

        /// Additional flush delay per extra terminal session.
        static let terminalFlushPerTerminalDelay: UInt64 = 4_000_000 // 4ms

        /// Maximum flush interval regardless of terminal count.
        static let terminalFlushMaxInterval: UInt64 = 32_000_000 // 32ms

        /// Maximum bytes flushed per terminal per frame.
        static let terminalFlushMaxBytesPerFrame = 196_608 // 192KB

        // --- Notifications ---

        /// How long to batch PR notification events before sending (ntfy).
        /// 10s is long enough to batch CI bot spam, short enough for timely single-PR alerts.
        static let notificationBatchWindow: UInt64 = 10_000_000_000 // 10s

        // --- AI ---

        /// Debounce before persisting chat thread changes to disk.
        static let chatPersistenceDebounce: TimeInterval = 0.5

        /// Wait before retrying after an AI API transient error.
        static let aiRetryDelay: TimeInterval = 2.0

        /// How often to poll a local LLM endpoint for health status (seconds).
        static let localHealthPollSeconds: Int = 5

        /// How long a local LLM health check result is considered fresh before re-polling.
        static let localHealthFreshnessSeconds: TimeInterval = 30

        /// Default request timeout for local LLM API calls.
        static let localDefaultRequestTimeoutSeconds: TimeInterval = 60

        // --- CLI Providers ---

        /// Timeout for probing whether a CLI tool (claude, codex) is authenticated.
        static let cliAuthProbeTimeout: TimeInterval = 10.0

        /// Grace period between SIGTERM and SIGKILL when cancelling a CLI subprocess.
        static let cliSigkillGrace: TimeInterval = 1.0

        /// How long to cache CLI tool discovery results (path + version) before re-probing.
        static let cliDiscoveryCacheTTL: TimeInterval = 300.0

        /// Delay before cleaning up tool-event state after a tool call completes.
        static let toolEventCleanupDelay: TimeInterval = 3.0

        /// Maximum age for per-spawn MCP config files before the stale-config sweep removes them.
        static let mcpConfigStaleSeconds: TimeInterval = 3600 // 1 hour

        /// Timeout for shortcut key recording before auto-cancelling.
        /// 5s gives users time to think about which key combo to use.
        static let shortcutRecordingTimeout: UInt64 = 5_000_000_000 // 5s

        // --- AI Harness ---

        /// Grace period before the harness cancels a hung AI turn (milliseconds).
        static let harnessCancelDeadlineMs: Int = 500

        // --- File Watcher Gate ---

        /// Cooldown after processing a file watcher event before accepting the next.
        /// Slightly wider than debounce rhythm to avoid overlapping refreshes.
        static let fileWatcherGateCooldown: UInt64 = 350_000_000 // 350ms

        /// Debounce before replaying a deferred file-tree refresh after the user
        /// switches back to the Code section. Coalesces rapid section flips and
        /// avoids racing the SwiftUI section-change render. (RT-003)
        static let sectionReturnReplayDelay: UInt64 = 250_000_000 // 250ms

    }

    enum Limits {
        /// Maximum recent repositories shown in sidebar and persisted
        static let maxRecentRepositories = 5
        /// Maximum reflog entries to display
        static let reflogEntryLimit = 50
        /// Maximum dangling commits to inspect during recovery snapshot scan
        static let maxDanglingSnapshots = 180
        /// Maximum matches returned by Find in Files
        static let maxFindInFilesMatches = 1000
        /// Maximum total matches to auto-expand in Find in Files
        static let maxFindInFilesAutoExpandedMatches = 60
        /// Maximum file groups to auto-expand in Find in Files
        static let maxFindInFilesAutoExpandedFiles = 10
        /// Initial number of matches to render for an expanded file result
        static let findInFilesInitialVisibleMatchesPerFile = 40
        /// Additional matches to reveal per "load more" action in Find in Files
        static let findInFilesVisibleMatchesPageSize = 80
        /// Maximum polling attempts when waiting for editor file to load
        static let maxEditorLocationWaitAttempts = 50
        /// Polling interval in milliseconds when waiting for editor file to load
        static let editorLocationWaitIntervalMs = 30
        /// Default soft-cap value used when a user enables the cap for the
        /// first time (the toggle needs a sensible starting amount). The user
        /// then edits the value freely via a numeric text field — there is no
        /// upper bound enforced here. Currency: USD.
        static let spendSoftCapDefaultUSD = 50
        /// Maximum untracked files to read content for AI context
        static let maxUntrackedFilesForContext = 5
        /// Maximum characters of file content to include in AI context
        static let maxFileContentPreviewLength = 500
        /// Maximum characters to show in clipboard preview text
        static let clipboardPreviewTruncationLength = 60
        /// Maximum document size for selection occurrence highlight scanning
        static let maxOccurrenceHighlightDocSize = 500_000
        /// Maximum occurrence highlight matches to render
        static let maxOccurrenceHighlightMatches = 500
        /// Maximum cached commit detail results (keyed by commit hash)
        static let commitDetailsCacheSize = 64
        /// Maximum cached commit file diff results (keyed by commitID:filePath)
        static let commitFileDiffCacheSize = 96
        /// Number of visible commits to prefetch details for in background
        static let commitDetailsPrefetchCount = 25
        /// Maximum age in days for dangling recovery snapshots before cleanup
        static let danglingSnapshotMaxAgeDays = 30
        /// Minimum dangling snapshot count to trigger automatic cleanup
        static let danglingSnapshotCleanupThreshold = 100
        /// Maximum number of parent-directory paths the FileWatcher coalescer may buffer
        /// before flushing immediately (safety ceiling for extreme burst writes).
        static let fileWatcherCoalesceMaxPaths: Int = 5_000

        // --- AI / Context Assembly ---

        /// Maximum tokens to include from a git diff in AI context.
        static let diffTokenCap = 8_000

        /// Maximum tokens to include from a folder mention in AI context.
        static let folderTokenCap = 6_000

        /// Maximum lines to preview per file inside a folder mention.
        static let folderFilePreviewLines = 20

        /// Maximum symbols to pass to the symbols tool per invocation.
        static let symbolsToolLimit = 20

        /// Maximum top symbols to embed in a RepoMemory snapshot.
        static let repoMemoryTopSymbolsLimit = 50

        /// Extra hop-score boost applied to the continue chip's next-message candidate.
        static let continueChipHopBoost = 10
    }

    enum RemoteAccess {
        static let defaultPort: UInt16 = 19_847
        static let wsPort: UInt16 = 19_848
        static let maxPendingEventsPerToken = 100
        static let heartbeatIntervalNanoseconds: UInt64 = 15_000_000_000
        static let tunnelURLTimeoutNanoseconds: UInt64 = 30_000_000_000
        static let tokenRotationInterval: TimeInterval = 86_400
        static let pairingTokenTTLSeconds: Int = 300
        static let maxConcurrentConnections = 2
        static let maxMessagesPerSecond = 20
        static let screenUpdateDebounceNanoseconds: UInt64 = 100_000_000
        static let aes256KeyByteLength = 32
        static let qrCodeSize: CGFloat = 200
        static let httpRequestBufferSize = 8192
    }

    enum UI {
        /// Standard frame for NSTextField inputs in alert dialogs
        static let alertInputFieldFrame = NSRect(x: 0, y: 0, width: 260, height: 24)
    }

    /// GitHub OAuth App client ID for Device Flow authentication.
    /// This is a public identifier (not a secret) — safe to embed in source.
    static let gitHubOAuthClientID = "Ov23liMlw7pMjQqLHcD0"

    enum Attachments {
        /// MIME types accepted for user-attached files in the chat input.
        static let acceptedMIMEs: [String] = [
            "image/png",
            "image/jpeg",
            "application/pdf"
        ]
    }

    enum Feature {
        /// When true, the AI harness sends SIGKILL to the subprocess on stop
        /// instead of relying solely on cooperative cancellation.
        /// Override via UserDefaults key "harness.processKillOnStop".
        static var harnessProcessKillOnStop: Bool {
            if let override = UserDefaults.standard.object(forKey: "harness.processKillOnStop") as? Bool {
                return override
            }
            return true
        }
    }
}
