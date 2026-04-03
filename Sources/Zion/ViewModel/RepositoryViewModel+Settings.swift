import Foundation
import SwiftUI
import CryptoKit

extension RepositoryViewModel {

    // MARK: - Git Availability

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

        if !isGitAvailable {
            showGitNotFoundAlert = true
        }
    }

    func installCommandLineTools() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["--install"]
        try? process.run()
    }

    // MARK: - Restore Editor Settings

    // Restore persisted editor settings from UserDefaults
    func restoreEditorSettings() {
        checkGitAvailability()

        let defaults = UserDefaults.standard
        if let themeRaw = defaults.string(forKey: UserDefaultsKeys.Editor.theme),
           let theme = EditorTheme(rawValue: themeRaw) {
            selectedTheme = theme
        }
        if defaults.object(forKey: UserDefaultsKeys.Editor.fontSize) != nil {
            editorFontSize = defaults.double(forKey: UserDefaultsKeys.Editor.fontSize)
        }
        if let family = defaults.string(forKey: UserDefaultsKeys.Editor.fontFamily) {
            editorFontFamily = family
        }
        if defaults.object(forKey: UserDefaultsKeys.Editor.lineSpacing) != nil {
            editorLineSpacing = defaults.double(forKey: UserDefaultsKeys.Editor.lineSpacing)
        }
        if defaults.object(forKey: UserDefaultsKeys.Editor.lineWrap) != nil {
            isLineWrappingEnabled = defaults.bool(forKey: UserDefaultsKeys.Editor.lineWrap)
        }
        if defaults.object(forKey: UserDefaultsKeys.Editor.tabSize) != nil {
            editorTabSize = defaults.integer(forKey: UserDefaultsKeys.Editor.tabSize)
        }
        if defaults.object(forKey: UserDefaultsKeys.Editor.useTabs) != nil {
            editorUseTabs = defaults.bool(forKey: UserDefaultsKeys.Editor.useTabs)
        }
        if defaults.object(forKey: UserDefaultsKeys.Editor.showRuler) != nil {
            editorShowRuler = defaults.bool(forKey: UserDefaultsKeys.Editor.showRuler)
        }
        if defaults.object(forKey: UserDefaultsKeys.Editor.rulerColumn) != nil {
            editorRulerColumn = defaults.integer(forKey: UserDefaultsKeys.Editor.rulerColumn)
        }
        if defaults.object(forKey: UserDefaultsKeys.Editor.autoCloseBrackets) != nil {
            editorAutoCloseBrackets = defaults.bool(forKey: UserDefaultsKeys.Editor.autoCloseBrackets)
        }
        if defaults.object(forKey: UserDefaultsKeys.Editor.autoCloseQuotes) != nil {
            editorAutoCloseQuotes = defaults.bool(forKey: UserDefaultsKeys.Editor.autoCloseQuotes)
        }
        if defaults.object(forKey: UserDefaultsKeys.Editor.letterSpacing) != nil {
            editorLetterSpacing = defaults.double(forKey: UserDefaultsKeys.Editor.letterSpacing)
        }
        if defaults.object(forKey: UserDefaultsKeys.Editor.highlightCurrentLine) != nil {
            editorHighlightCurrentLine = defaults.bool(forKey: UserDefaultsKeys.Editor.highlightCurrentLine)
        }
        if defaults.object(forKey: UserDefaultsKeys.Editor.bracketPairHighlight) != nil {
            editorBracketPairHighlight = defaults.bool(forKey: UserDefaultsKeys.Editor.bracketPairHighlight)
        }
        if defaults.object(forKey: UserDefaultsKeys.Editor.showIndentGuides) != nil {
            editorShowIndentGuides = defaults.bool(forKey: UserDefaultsKeys.Editor.showIndentGuides)
        }
        if defaults.object(forKey: UserDefaultsKeys.Editor.formatOnSave) != nil {
            editorFormatOnSave = defaults.bool(forKey: UserDefaultsKeys.Editor.formatOnSave)
        }
        if defaults.object(forKey: UserDefaultsKeys.Editor.jsonSortKeys) != nil {
            editorJsonSortKeys = defaults.bool(forKey: UserDefaultsKeys.Editor.jsonSortKeys)
        }
        if defaults.object(forKey: UserDefaultsKeys.Editor.trimTrailingWhitespace) != nil {
            editorTrimTrailingWhitespace = defaults.bool(forKey: UserDefaultsKeys.Editor.trimTrailingWhitespace)
        }
        if let rw = defaults.string(forKey: UserDefaultsKeys.Editor.renderWhitespace) {
            editorRenderWhitespace = rw
        }
        if defaults.object(forKey: UserDefaultsKeys.Editor.topPadding) != nil {
            editorTopPadding = defaults.double(forKey: UserDefaultsKeys.Editor.topPadding)
        }
        if defaults.object(forKey: UserDefaultsKeys.Editor.scrollPastEnd) != nil {
            editorScrollPastEnd = defaults.bool(forKey: UserDefaultsKeys.Editor.scrollPastEnd)
        }
        // Terminal font settings
        if defaults.object(forKey: UserDefaultsKeys.Terminal.fontSize) != nil {
            terminalFontSize = defaults.double(forKey: UserDefaultsKeys.Terminal.fontSize)
        }
        if let family = defaults.string(forKey: UserDefaultsKeys.Terminal.fontFamily) {
            terminalFontFamily = MonospaceFontResolver.migratedTerminalName(family)
        }
        // Terminal transparency settings
        if defaults.object(forKey: UserDefaultsKeys.Terminal.opacity) != nil {
            terminalOpacity = defaults.double(forKey: UserDefaultsKeys.Terminal.opacity)
        }
        // AI provider
        if let aiRaw = defaults.string(forKey: UserDefaultsKeys.AI.provider),
           let provider = AIProvider(rawValue: aiRaw) {
            aiProvider = provider
        }
        if let modeRaw = defaults.string(forKey: UserDefaultsKeys.AI.mode),
           let mode = AIMode(rawValue: modeRaw) {
            aiMode = mode
        }
        // Commit message style
        if let styleRaw = defaults.string(forKey: UserDefaultsKeys.AI.commitMessageStyle),
           let style = CommitMessageStyle(rawValue: styleRaw) {
            commitMessageStyle = style
        }
        // ntfy Push Notifications
        if let topic = defaults.string(forKey: UserDefaultsKeys.Ntfy.topic) {
            ntfyTopic = topic
        }
        if let server = defaults.string(forKey: UserDefaultsKeys.Ntfy.serverURL), !server.isEmpty {
            ntfyServerURL = server
        }
        if let events = defaults.stringArray(forKey: UserDefaultsKeys.Ntfy.enabledEvents) {
            ntfyEnabledEvents = events
        }
        if defaults.object(forKey: UserDefaultsKeys.Ntfy.enabled) != nil {
            ntfyEnabled = defaults.bool(forKey: UserDefaultsKeys.Ntfy.enabled)
        }
        if defaults.object(forKey: UserDefaultsKeys.Ntfy.localNotifications) != nil {
            ntfyLocalNotificationsEnabled = defaults.bool(forKey: UserDefaultsKeys.Ntfy.localNotifications)
        }
        if defaults.object(forKey: UserDefaultsKeys.Notifications.prPollingInterval) != nil {
            prPollingIntervalMinutes = Self.sanitizedPRPollingIntervalMinutes(defaults.integer(forKey: UserDefaultsKeys.Notifications.prPollingInterval))
        }
        // AI review settings
        if defaults.object(forKey: UserDefaultsKeys.AI.preCommitReview) != nil {
            preCommitReviewEnabled = defaults.bool(forKey: UserDefaultsKeys.AI.preCommitReview)
        }
        if defaults.object(forKey: UserDefaultsKeys.AI.transferSupportHints) != nil {
            aiTransferSupportHintsEnabled = defaults.bool(forKey: UserDefaultsKeys.AI.transferSupportHints)
        }
        // File browser
        if defaults.object(forKey: UserDefaultsKeys.FileBrowser.showHiddenFiles) != nil {
            showDotfiles = defaults.bool(forKey: UserDefaultsKeys.FileBrowser.showHiddenFiles)
        }
        // Mobile Remote Access
        if defaults.object(forKey: UserDefaultsKeys.MobileAccess.enabled) != nil {
            isMobileAccessEnabled = defaults.bool(forKey: UserDefaultsKeys.MobileAccess.enabled)
            if isMobileAccessEnabled {
                enableRemoteAccess()
            }
        }
    }

    // MARK: - Restore Last Repository

    enum RestoreLastRepositoryResult {
        case opened(URL)
        case none
        case missing(URL)
    }

    @discardableResult
    func restoreLastRepository() -> RestoreLastRepositoryResult {
        guard let urls = try? JSONDecoder().decode([URL].self, from: recentReposData),
              let lastURL = urls.first else {
            return .none
        }
        guard FileManager.default.fileExists(atPath: lastURL.path) else {
            return .missing(lastURL)
        }
        openRepository(lastURL)
        return .opened(lastURL)
    }

    func hasRestorableRecentRepository() -> Bool {
        guard let urls = try? JSONDecoder().decode([URL].self, from: recentReposData),
              let lastURL = urls.first else { return false }
        return FileManager.default.fileExists(atPath: lastURL.path)
    }

    // MARK: - Sync Settings from Defaults

    /// Sync all settings from UserDefaults (called when Settings window changes values via @AppStorage)
    func syncSettingsFromDefaults() {
        let defaults = UserDefaults.standard

        // MARK: Editor settings
        if let themeRaw = defaults.string(forKey: UserDefaultsKeys.Editor.theme),
           let theme = EditorTheme(rawValue: themeRaw), theme != selectedTheme {
            selectedTheme = theme
        }
        let fs = defaults.double(forKey: UserDefaultsKeys.Editor.fontSize)
        if fs > 0 && fs != editorFontSize { editorFontSize = fs }
        if let family = defaults.string(forKey: UserDefaultsKeys.Editor.fontFamily), family != editorFontFamily {
            editorFontFamily = family
        }
        if defaults.object(forKey: UserDefaultsKeys.Editor.lineSpacing) != nil {
            let ls = defaults.double(forKey: UserDefaultsKeys.Editor.lineSpacing)
            if ls != editorLineSpacing { editorLineSpacing = ls }
        }

        if defaults.object(forKey: UserDefaultsKeys.Editor.lineWrap) != nil {
            let lw = defaults.bool(forKey: UserDefaultsKeys.Editor.lineWrap)
            if lw != isLineWrappingEnabled { isLineWrappingEnabled = lw }
        }

        let ts = defaults.integer(forKey: UserDefaultsKeys.Editor.tabSize)
        if ts > 0 && ts != editorTabSize { editorTabSize = ts }
        let ut = defaults.bool(forKey: UserDefaultsKeys.Editor.useTabs)
        if ut != editorUseTabs { editorUseTabs = ut }
        let sr = defaults.bool(forKey: UserDefaultsKeys.Editor.showRuler)
        if sr != editorShowRuler { editorShowRuler = sr }
        let rc = defaults.integer(forKey: UserDefaultsKeys.Editor.rulerColumn)
        if rc > 0 && rc != editorRulerColumn { editorRulerColumn = rc }
        let acb = defaults.bool(forKey: UserDefaultsKeys.Editor.autoCloseBrackets)
        if acb != editorAutoCloseBrackets { editorAutoCloseBrackets = acb }
        let acq = defaults.bool(forKey: UserDefaultsKeys.Editor.autoCloseQuotes)
        if acq != editorAutoCloseQuotes { editorAutoCloseQuotes = acq }
        let els = defaults.double(forKey: UserDefaultsKeys.Editor.letterSpacing)
        if els != editorLetterSpacing { editorLetterSpacing = els }
        let hcl = defaults.bool(forKey: UserDefaultsKeys.Editor.highlightCurrentLine)
        if hcl != editorHighlightCurrentLine { editorHighlightCurrentLine = hcl }
        let bph = defaults.bool(forKey: UserDefaultsKeys.Editor.bracketPairHighlight)
        if bph != editorBracketPairHighlight { editorBracketPairHighlight = bph }
        let sig = defaults.bool(forKey: UserDefaultsKeys.Editor.showIndentGuides)
        if sig != editorShowIndentGuides { editorShowIndentGuides = sig }
        let fos = defaults.bool(forKey: UserDefaultsKeys.Editor.formatOnSave)
        if fos != editorFormatOnSave { editorFormatOnSave = fos }
        let jsk = defaults.bool(forKey: UserDefaultsKeys.Editor.jsonSortKeys)
        if jsk != editorJsonSortKeys { editorJsonSortKeys = jsk }
        let ttw = defaults.bool(forKey: UserDefaultsKeys.Editor.trimTrailingWhitespace)
        if ttw != editorTrimTrailingWhitespace { editorTrimTrailingWhitespace = ttw }
        if let rw = defaults.string(forKey: UserDefaultsKeys.Editor.renderWhitespace), rw != editorRenderWhitespace {
            editorRenderWhitespace = rw
        }
        if defaults.object(forKey: UserDefaultsKeys.Editor.topPadding) != nil {
            let tp = defaults.double(forKey: UserDefaultsKeys.Editor.topPadding)
            if tp != editorTopPadding { editorTopPadding = tp }
        }
        let spe = defaults.bool(forKey: UserDefaultsKeys.Editor.scrollPastEnd)
        if spe != editorScrollPastEnd { editorScrollPastEnd = spe }

        // MARK: Terminal settings
        let tfs = defaults.double(forKey: UserDefaultsKeys.Terminal.fontSize)
        if tfs > 0 && tfs != terminalFontSize { terminalFontSize = tfs }
        if let tFamily = defaults.string(forKey: UserDefaultsKeys.Terminal.fontFamily) {
            let migrated = MonospaceFontResolver.migratedTerminalName(tFamily)
            if migrated != terminalFontFamily { terminalFontFamily = migrated }
        }
        if defaults.object(forKey: UserDefaultsKeys.Terminal.opacity) != nil {
            let top = defaults.double(forKey: UserDefaultsKeys.Terminal.opacity)
            if top != terminalOpacity { terminalOpacity = top }
        }

        // MARK: AI settings
        if let aiRaw = defaults.string(forKey: UserDefaultsKeys.AI.provider),
           let provider = AIProvider(rawValue: aiRaw), provider != aiProvider {
            aiProvider = provider
        }
        if let modeRaw = defaults.string(forKey: UserDefaultsKeys.AI.mode),
           let mode = AIMode(rawValue: modeRaw), mode != aiMode {
            aiMode = mode
        }
        if let styleRaw = defaults.string(forKey: UserDefaultsKeys.AI.commitMessageStyle),
           let style = CommitMessageStyle(rawValue: styleRaw), style != commitMessageStyle {
            commitMessageStyle = style
        }
        let pcr = defaults.bool(forKey: UserDefaultsKeys.AI.preCommitReview)
        if pcr != preCommitReviewEnabled { preCommitReviewEnabled = pcr }
        if defaults.object(forKey: UserDefaultsKeys.AI.transferSupportHints) != nil {
            let ath = defaults.bool(forKey: UserDefaultsKeys.AI.transferSupportHints)
            if ath != aiTransferSupportHintsEnabled { aiTransferSupportHintsEnabled = ath }
        }

        // MARK: ntfy settings
        if let topic = defaults.string(forKey: UserDefaultsKeys.Ntfy.topic), topic != ntfyTopic {
            ntfyTopic = topic
        }
        if let server = defaults.string(forKey: UserDefaultsKeys.Ntfy.serverURL), !server.isEmpty, server != ntfyServerURL {
            ntfyServerURL = server
        }
        if let events = defaults.stringArray(forKey: UserDefaultsKeys.Ntfy.enabledEvents), events != ntfyEnabledEvents {
            ntfyEnabledEvents = events
        }
        if defaults.object(forKey: UserDefaultsKeys.Ntfy.enabled) != nil {
            let enabled = defaults.bool(forKey: UserDefaultsKeys.Ntfy.enabled)
            if enabled != ntfyEnabled { ntfyEnabled = enabled }
        }
        if defaults.object(forKey: UserDefaultsKeys.Ntfy.localNotifications) != nil {
            let nln = defaults.bool(forKey: UserDefaultsKeys.Ntfy.localNotifications)
            if nln != ntfyLocalNotificationsEnabled { ntfyLocalNotificationsEnabled = nln }
        }
        if defaults.object(forKey: UserDefaultsKeys.Notifications.prPollingInterval) != nil {
            let interval = Self.sanitizedPRPollingIntervalMinutes(defaults.integer(forKey: UserDefaultsKeys.Notifications.prPollingInterval))
            if interval != prPollingIntervalMinutes {
                prPollingIntervalMinutes = interval
                if repositoryURL != nil {
                    startPRPollingTimer()
                }
            }
        }

        // MARK: File browser
        if defaults.object(forKey: UserDefaultsKeys.FileBrowser.showHiddenFiles) != nil {
            let sd = defaults.bool(forKey: UserDefaultsKeys.FileBrowser.showHiddenFiles)
            if sd != showDotfiles { showDotfiles = sd }
        }

        // MARK: Mobile Remote Access
        if defaults.object(forKey: UserDefaultsKeys.MobileAccess.enabled) != nil {
            let mae = defaults.bool(forKey: UserDefaultsKeys.MobileAccess.enabled)
            if mae != isMobileAccessEnabled {
                isMobileAccessEnabled = mae
                if mae {
                    enableRemoteAccess()
                } else {
                    disableRemoteAccess()
                }
            }
        }

        // Handle regenerate key request from Settings
        if RemoteAccessState.shared.shouldRegenerateKey {
            RemoteAccessState.shared.shouldRegenerateKey = false
            regeneratePairingKey()
        }

        // Handle keep-awake duration change from Settings
        if RemoteAccessState.shared.keepAwakeChanged {
            RemoteAccessState.shared.keepAwakeChanged = false
            if isMobileAccessEnabled {
                acquireSleepAssertionIfNeeded()
            }
        }
    }

    // MARK: - Recent Repositories

    func loadRecentRepositories() {
        if let urls = try? JSONDecoder().decode([URL].self, from: recentReposData) {
            let normalized = normalizeRecentRepositories(urls)
            recentRepositories = normalized
            if let encoded = try? JSONEncoder().encode(normalized) {
                recentReposData = encoded
            }
            refreshRecentWorktreeCounts()
            refreshRecentChangedCounts()
        }
    }

    func saveRecentRepository(_ url: URL) {
        let canonical = canonicalRecentRepositoryURL(for: url)
        var current = (try? JSONDecoder().decode([URL].self, from: recentReposData)) ?? []
        current = normalizeRecentRepositories(current)
        current.removeAll { $0 == canonical }
        current.insert(canonical, at: 0)
        let limited = Array(current.prefix(10))
        if let encoded = try? JSONEncoder().encode(limited) {
            recentReposData = encoded
            recentRepositories = limited
            refreshRecentWorktreeCounts()
        }
    }

    func recentRepositoryRoot(for url: URL?) -> URL? {
        guard let url else { return nil }
        return canonicalRecentRepositoryURL(for: url)
    }

    func recentChangedCount(for recentRoot: URL) -> Int? {
        if recentRepositoryRoot(for: repositoryURL) == recentRoot {
            return uncommittedCount
        }
        return backgroundRepoChangedFiles[recentRoot]
    }

    func normalizeRecentRepositories(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        var ordered: [URL] = []
        for url in urls {
            let canonical = canonicalRecentRepositoryURL(for: url)
            if seen.insert(canonical.path).inserted {
                ordered.append(canonical)
            }
        }
        return ordered
    }

    func canonicalRecentRepositoryURL(for url: URL) -> URL {
        let standardized = url.standardizedFileURL
        let gitMarker = standardized.appendingPathComponent(".git")
        var isDirectory = ObjCBool(false)

        if FileManager.default.fileExists(atPath: gitMarker.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return standardized
        }

        guard FileManager.default.fileExists(atPath: gitMarker.path),
              let markerContent = try? String(contentsOf: gitMarker, encoding: .utf8),
              let gitdirLine = markerContent
                .split(separator: "\n")
                .map(String.init)
                .first(where: { $0.hasPrefix("gitdir:") }) else {
            return standardized
        }

        let gitdirRaw = gitdirLine.replacingOccurrences(of: "gitdir:", with: "").clean
        guard !gitdirRaw.isEmpty else { return standardized }

        let gitdirURL: URL = if gitdirRaw.hasPrefix("/") {
            URL(fileURLWithPath: gitdirRaw).standardizedFileURL
        } else {
            standardized.appendingPathComponent(gitdirRaw).standardizedFileURL
        }

        let gitdirPath = gitdirURL.path
        if let worktreeRange = gitdirPath.range(of: "/.git/worktrees/") {
            let rootPath = String(gitdirPath[..<worktreeRange.lowerBound])
            return URL(fileURLWithPath: rootPath).standardizedFileURL
        }

        if gitdirPath.hasSuffix("/.git") {
            let rootPath = String(gitdirPath.dropLast("/.git".count))
            return URL(fileURLWithPath: rootPath).standardizedFileURL
        }

        return standardized
    }

    func refreshRecentWorktreeCounts() {
        let roots = recentRepositories
        Task {
            var counts: [URL: Int] = [:]
            for root in roots {
                guard FileManager.default.fileExists(atPath: root.path) else {
                    counts[root] = 0
                    continue
                }
                if let output = try? await worker.runAction(args: ["worktree", "list", "--porcelain"], in: root) {
                    let total = output
                        .split(separator: "\n", omittingEmptySubsequences: true)
                        .filter { $0.hasPrefix("worktree ") }
                        .count
                    counts[root] = max(total - 1, 0)
                } else {
                    counts[root] = 0
                }
            }
            recentWorktreeCounts = counts
        }
    }

    func refreshRecentChangedCounts() {
        let roots = recentRepositories
        Task {
            for root in roots {
                guard FileManager.default.fileExists(atPath: root.path) else { continue }
                // Skip the currently active repo (it uses live uncommittedCount)
                if canonicalRecentRepositoryURL(for: repositoryURL ?? URL(fileURLWithPath: "/")) == root { continue }
                // Skip repos already monitored via background stash
                if backgroundRepoStates.keys.contains(where: { canonicalRecentRepositoryURL(for: $0) == root }) { continue }
                await updateChangedFileCount(for: root)
            }
        }
    }

    // MARK: - Avatars

    /// Fetch avatar for a hosting provider username (GitHub, GitLab).
    /// Uses the same shared `avatarCache` as Gravatar avatars.
    func avatarImage(forUsername username: String, prURL: String) -> NSImage? {
        guard !username.isEmpty else { return nil }
        guard UserDefaults.standard.bool(forKey: UserDefaultsKeys.General.graphAuthorAvatarsEnabled) else { return nil }
        let key = "user:\(username)"
        if let cached = avatarCache.object(forKey: key as NSString) { return cached }
        if !avatarDownloadTasks.contains(key) {
            avatarDownloadTasks.insert(key)
            Task { [weak self] in
                guard let self else { return }
                await avatarSemaphore.acquire()
                defer { Task { await self.avatarSemaphore.release() } }
                let urlString: String?
                if prURL.contains("github.com") {
                    urlString = "https://github.com/\(username).png?size=40"
                } else if prURL.contains("gitlab.com") {
                    urlString = "https://gitlab.com/\(username).png?width=40"
                } else {
                    urlString = nil
                }
                guard let urlString, let url = URL(string: urlString) else {
                    avatarDownloadTasks.remove(key)
                    return
                }
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if let image = NSImage(data: data) {
                        avatarCache.setObject(image, forKey: key as NSString)
                    }
                } catch {}
                avatarDownloadTasks.remove(key)
            }
        }
        return nil
    }

    func avatarImage(for email: String) -> NSImage? {
        guard !email.isEmpty else { return nil }
        guard UserDefaults.standard.bool(forKey: UserDefaultsKeys.General.graphAuthorAvatarsEnabled) else { return nil }
        let key = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let cached = avatarCache.object(forKey: key as NSString) { return cached }
        // Start download if not already in-flight
        if !avatarDownloadTasks.contains(key) {
            avatarDownloadTasks.insert(key)
            Task { [weak self] in
                guard let self else { return }
                await avatarSemaphore.acquire()
                defer { Task { await self.avatarSemaphore.release() } }
                let hash = Insecure.MD5.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
                guard let url = URL(string: "https://gravatar.com/avatar/\(hash)?s=40&d=identicon") else { return }
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if let image = NSImage(data: data) {
                        avatarCache.setObject(image, forKey: key as NSString)
                    }
                } catch {
                    // Silently fail — identicon fallback handled by Gravatar
                }
                avatarDownloadTasks.remove(key)
            }
        }
        return nil
    }


}
