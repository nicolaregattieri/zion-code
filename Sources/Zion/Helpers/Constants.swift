import AppKit
import Foundation

enum Constants {
    /// ASCII Unit Separator (0x1F) used as field delimiter in git format strings
    static let gitFieldSeparator = Character(UnicodeScalar(0x1F)!)
    /// ASCII Record Separator (0x1E) used as record delimiter in git format strings
    static let gitRecordSeparator = Character(UnicodeScalar(0x1E)!)

    enum Timing {
        /// Delay before starting deferred repository loads after a repo switch (250ms)
        static let repositorySwitchDeferral: UInt64 = 250_000_000
        /// Polling interval while waiting for busy state to clear during repo switch (50ms)
        static let repositorySwitchPollInterval: UInt64 = 50_000_000
        /// Maximum number of polling attempts during repo switch wait
        static let maxRepositorySwitchAttempts = 40
        /// Interval between background fetch cycles (60s)
        static let backgroundFetchInterval: UInt64 = 60_000_000_000
        /// Interval between background monitor / auto-refresh cycles (30s)
        static let backgroundMonitorInterval: UInt64 = 30_000_000_000
        /// Interval between PR review queue polling cycles (5min)
        static let prPollingInterval: UInt64 = 5 * 60 * 1_000_000_000
        /// Delay before opening conflict resolver after transfer support (600ms)
        static let transferSupportDelay: UInt64 = 600_000_000
    }

    enum Limits {
        /// Maximum reflog entries to display
        static let reflogEntryLimit = 50
        /// Maximum dangling commits to inspect during recovery snapshot scan
        static let maxDanglingSnapshots = 180
        /// Maximum matches returned by Find in Files
        static let maxFindInFilesMatches = 1000
        /// Maximum polling attempts when waiting for editor file to load
        static let maxEditorLocationWaitAttempts = 50
        /// Polling interval in milliseconds when waiting for editor file to load
        static let editorLocationWaitIntervalMs = 30
        /// Maximum untracked files to read content for AI context
        static let maxUntrackedFilesForContext = 5
        /// Maximum characters of file content to include in AI context
        static let maxFileContentPreviewLength = 500
        /// Maximum characters to show in clipboard preview text
        static let clipboardPreviewTruncationLength = 60
    }

    enum RemoteAccess {
        static let defaultPort: UInt16 = 19_847
        static let maxScreenUpdateLines = 50
        static let heartbeatIntervalNanoseconds: UInt64 = 15_000_000_000
        static let tunnelURLTimeoutNanoseconds: UInt64 = 30_000_000_000
        static let tokenRotationInterval: TimeInterval = 86_400
        static let pairingTokenTTLSeconds: Int = 300
        static let maxConcurrentConnections = 2
        static let maxMessagesPerSecond = 20
        static let screenUpdateDebounceNanoseconds: UInt64 = 200_000_000
        static let aes256KeyByteLength = 32
        static let qrCodeSize: CGFloat = 200
        static let httpRequestBufferSize = 8192
    }

    enum UI {
        /// Standard frame for NSTextField inputs in alert dialogs
        static let alertInputFieldFrame = NSRect(x: 0, y: 0, width: 260, height: 24)
    }
}
