import Foundation

// MARK: - Centralized UserDefaults Key Constants
// Every key used with UserDefaults.standard or @AppStorage is defined here.
// Usage: UserDefaultsKeys.Editor.theme, UserDefaultsKeys.Terminal.fontSize, etc.

enum UserDefaultsKeys {

    // MARK: - Editor

    enum Editor {
        static let theme = "editor.theme"
        static let fontFamily = "editor.fontFamily"
        static let fontSize = "editor.fontSize"
        static let lineSpacing = "editor.lineSpacing"
        static let letterSpacing = "editor.letterSpacing"
        static let tabSize = "editor.tabSize"
        static let useTabs = "editor.useTabs"
        static let autoCloseBrackets = "editor.autoCloseBrackets"
        static let autoCloseQuotes = "editor.autoCloseQuotes"
        static let bracketPairHighlight = "editor.bracketPairHighlight"
        static let lineWrap = "editor.lineWrap"
        static let showRuler = "editor.showRuler"
        static let rulerColumn = "editor.rulerColumn"
        static let highlightCurrentLine = "editor.highlightCurrentLine"
        static let showIndentGuides = "editor.showIndentGuides"
        static let formatOnSave = "editor.formatOnSave"
        static let jsonSortKeys = "editor.jsonSortKeys"
        static let showBreadcrumb = "editor.showBreadcrumb"
    }

    // MARK: - Terminal

    enum Terminal {
        static let fontSize = "terminal.fontSize"
        static let fontFamily = "terminal.fontFamily"
        static let opacity = "terminal.opacity"
        static let scrollbackSize = "terminal.scrollbackSize"
        static let bellMode = "terminal.bellMode"
        static let openHyperlinks = "terminal.openHyperlinks"
        static let copyOnSelect = "terminal.copyOnSelect"
        static let aiImageDisplay = "terminal.aiImageDisplay"
    }

    // MARK: - Speech

    enum Speech {
        static let engine = "speech.engine"
        static let locale = "speech.locale"
    }

    // MARK: - AI

    enum AI {
        static let provider = "zion.aiProvider"
        static let mode = "zion.aiMode"
        static let commitMessageStyle = "zion.commitMessageStyle"
        static let preCommitReview = "zion.preCommitReview"
        static let transferSupportHints = "zion.aiTransferSupportHints"
    }

    // MARK: - Repo Memory

    enum RepoMemory {
        static let activeRepoName = "zion.repoMemory.activeRepoName"
        static let lastRefresh = "zion.repoMemory.lastRefresh"
        static let ready = "zion.repoMemory.ready"
    }

    // MARK: - Ntfy (Push Notifications)

    enum Ntfy {
        static let enabled = "zion.ntfy.enabled"
        static let topic = "zion.ntfy.topic"
        static let serverURL = "zion.ntfy.serverURL"
        static let localNotifications = "zion.ntfy.localNotifications"
        static let enabledEvents = "zion.ntfy.enabledEvents"
    }

    // MARK: - Notifications

    enum Notifications {
        static let prPollingInterval = "zion.prPollingInterval"
        static let autoReviewAssignedPRs = "zion.autoReviewAssignedPRs"
    }

    // MARK: - Mobile Access

    enum MobileAccess {
        static let enabled = "zion.mobileAccess.enabled"
        static let keepAwakeDuration = "zion.mobileAccess.keepAwakeDuration"
    }

    // MARK: - Appearance & General

    enum General {
        static let uiLanguage = "zion.uiLanguage"
        static let appearance = "zion.appearance"
        static let confirmationMode = "zion.confirmationMode"
        static let zionModeEnabled = "zion.zionModeEnabled"
        static let graphAuthorAvatarsEnabled = "zion.graphAuthorAvatarsEnabled"
        static let hasCompletedOnboarding = "zion.hasCompletedOnboarding"
        static let hasCompletedFeatureTour = "zion.hasCompletedFeatureTour"
        static let hasOpenedRepositoryOnce = "zion.hasOpenedRepositoryOnce"
        static let zenModeEnabled = "zion.zenModeEnabled"
        static let preZionModeTheme = "zion.preZionModeTheme"
        static let recentRepositories = "zion.recentRepositories"
    }

    // MARK: - Git Hosting

    enum GitHosting {
        static let gitlabHost = "zion.gitlab.host"
        static let bitbucketUsername = "zion.bitbucket.username"
    }

    // MARK: - File Browser

    enum FileBrowser {
        static let showHiddenFiles = "fileBrowser.showHiddenFiles"
    }

    // MARK: - Sidebar

    enum Sidebar {
        static let recentsExpanded = "zion.sidebar.recentsExpanded"
    }

    // MARK: - Bridge

    enum Bridge {
        static let smartSync = "zion.bridge.smartSync"
    }

    // MARK: - Clipboard

    enum Clipboard {
        static let collapsed = "clipboard.collapsed"
    }
}
