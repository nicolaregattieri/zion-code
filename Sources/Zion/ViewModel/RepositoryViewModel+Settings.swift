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
        if defaults.object(forKey: "editor.tabSize") != nil {
            editorTabSize = defaults.integer(forKey: "editor.tabSize")
        }
        if defaults.object(forKey: "editor.useTabs") != nil {
            editorUseTabs = defaults.bool(forKey: "editor.useTabs")
        }
        if defaults.object(forKey: "editor.showRuler") != nil {
            editorShowRuler = defaults.bool(forKey: "editor.showRuler")
        }
        if defaults.object(forKey: "editor.rulerColumn") != nil {
            editorRulerColumn = defaults.integer(forKey: "editor.rulerColumn")
        }
        if defaults.object(forKey: "editor.autoCloseBrackets") != nil {
            editorAutoCloseBrackets = defaults.bool(forKey: "editor.autoCloseBrackets")
        }
        if defaults.object(forKey: "editor.autoCloseQuotes") != nil {
            editorAutoCloseQuotes = defaults.bool(forKey: "editor.autoCloseQuotes")
        }
        if defaults.object(forKey: "editor.letterSpacing") != nil {
            editorLetterSpacing = defaults.double(forKey: "editor.letterSpacing")
        }
        if defaults.object(forKey: "editor.highlightCurrentLine") != nil {
            editorHighlightCurrentLine = defaults.bool(forKey: "editor.highlightCurrentLine")
        }
        if defaults.object(forKey: "editor.bracketPairHighlight") != nil {
            editorBracketPairHighlight = defaults.bool(forKey: "editor.bracketPairHighlight")
        }
        if defaults.object(forKey: "editor.showIndentGuides") != nil {
            editorShowIndentGuides = defaults.bool(forKey: "editor.showIndentGuides")
        }
        if defaults.object(forKey: "editor.formatOnSave") != nil {
            editorFormatOnSave = defaults.bool(forKey: "editor.formatOnSave")
        }
        if defaults.object(forKey: "editor.jsonSortKeys") != nil {
            editorJsonSortKeys = defaults.bool(forKey: "editor.jsonSortKeys")
        }
        // Terminal font settings
        if defaults.object(forKey: "terminal.fontSize") != nil {
            terminalFontSize = defaults.double(forKey: "terminal.fontSize")
        }
        if let family = defaults.string(forKey: "terminal.fontFamily") {
            terminalFontFamily = MonospaceFontResolver.migratedTerminalName(family)
        }
        // Terminal transparency settings
        if defaults.object(forKey: "terminal.opacity") != nil {
            terminalOpacity = defaults.double(forKey: "terminal.opacity")
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
        if defaults.object(forKey: "zion.ntfy.localNotifications") != nil {
            ntfyLocalNotificationsEnabled = defaults.bool(forKey: "zion.ntfy.localNotifications")
        }
        // AI review settings
        if defaults.object(forKey: "zion.preCommitReview") != nil {
            preCommitReviewEnabled = defaults.bool(forKey: "zion.preCommitReview")
        }
        if defaults.object(forKey: "zion.autoExplainDiffs") != nil {
            autoExplainDiffs = defaults.bool(forKey: "zion.autoExplainDiffs")
        }
        if let depthRaw = defaults.string(forKey: "zion.diffExplanationDepth"),
           let depth = DiffExplanationDepth(rawValue: depthRaw) {
            diffExplanationDepth = depth
        }
        if defaults.object(forKey: "zion.aiTransferSupportHints") != nil {
            aiTransferSupportHintsEnabled = defaults.bool(forKey: "zion.aiTransferSupportHints")
        }
        // File browser
        if defaults.object(forKey: "fileBrowser.showHiddenFiles") != nil {
            showDotfiles = defaults.bool(forKey: "fileBrowser.showHiddenFiles")
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
        if let themeRaw = defaults.string(forKey: "editor.theme"),
           let theme = EditorTheme(rawValue: themeRaw), theme != selectedTheme {
            selectedTheme = theme
        }
        let fs = defaults.double(forKey: "editor.fontSize")
        if fs > 0 && fs != editorFontSize { editorFontSize = fs }
        if let family = defaults.string(forKey: "editor.fontFamily"), family != editorFontFamily {
            editorFontFamily = family
        }
        if defaults.object(forKey: "editor.lineSpacing") != nil {
            let ls = defaults.double(forKey: "editor.lineSpacing")
            if ls != editorLineSpacing { editorLineSpacing = ls }
        }

        let lw = defaults.bool(forKey: "editor.lineWrap")
        if lw != isLineWrappingEnabled { isLineWrappingEnabled = lw }

        let ts = defaults.integer(forKey: "editor.tabSize")
        if ts > 0 && ts != editorTabSize { editorTabSize = ts }
        let ut = defaults.bool(forKey: "editor.useTabs")
        if ut != editorUseTabs { editorUseTabs = ut }
        let sr = defaults.bool(forKey: "editor.showRuler")
        if sr != editorShowRuler { editorShowRuler = sr }
        let rc = defaults.integer(forKey: "editor.rulerColumn")
        if rc > 0 && rc != editorRulerColumn { editorRulerColumn = rc }
        let acb = defaults.bool(forKey: "editor.autoCloseBrackets")
        if acb != editorAutoCloseBrackets { editorAutoCloseBrackets = acb }
        let acq = defaults.bool(forKey: "editor.autoCloseQuotes")
        if acq != editorAutoCloseQuotes { editorAutoCloseQuotes = acq }
        let els = defaults.double(forKey: "editor.letterSpacing")
        if els != editorLetterSpacing { editorLetterSpacing = els }
        let hcl = defaults.bool(forKey: "editor.highlightCurrentLine")
        if hcl != editorHighlightCurrentLine { editorHighlightCurrentLine = hcl }
        let bph = defaults.bool(forKey: "editor.bracketPairHighlight")
        if bph != editorBracketPairHighlight { editorBracketPairHighlight = bph }
        let sig = defaults.bool(forKey: "editor.showIndentGuides")
        if sig != editorShowIndentGuides { editorShowIndentGuides = sig }
        let fos = defaults.bool(forKey: "editor.formatOnSave")
        if fos != editorFormatOnSave { editorFormatOnSave = fos }
        let jsk = defaults.bool(forKey: "editor.jsonSortKeys")
        if jsk != editorJsonSortKeys { editorJsonSortKeys = jsk }

        // MARK: Terminal settings
        let tfs = defaults.double(forKey: "terminal.fontSize")
        if tfs > 0 && tfs != terminalFontSize { terminalFontSize = tfs }
        if let tFamily = defaults.string(forKey: "terminal.fontFamily") {
            let migrated = MonospaceFontResolver.migratedTerminalName(tFamily)
            if migrated != terminalFontFamily { terminalFontFamily = migrated }
        }
        if defaults.object(forKey: "terminal.opacity") != nil {
            let top = defaults.double(forKey: "terminal.opacity")
            if top != terminalOpacity { terminalOpacity = top }
        }

        // MARK: AI settings
        if let aiRaw = defaults.string(forKey: "zion.aiProvider"),
           let provider = AIProvider(rawValue: aiRaw), provider != aiProvider {
            aiProvider = provider
        }
        if let styleRaw = defaults.string(forKey: "zion.commitMessageStyle"),
           let style = CommitMessageStyle(rawValue: styleRaw), style != commitMessageStyle {
            commitMessageStyle = style
        }
        let pcr = defaults.bool(forKey: "zion.preCommitReview")
        if pcr != preCommitReviewEnabled { preCommitReviewEnabled = pcr }
        let aed = defaults.bool(forKey: "zion.autoExplainDiffs")
        if aed != autoExplainDiffs { autoExplainDiffs = aed }
        if let depthRaw = defaults.string(forKey: "zion.diffExplanationDepth"),
           let depth = DiffExplanationDepth(rawValue: depthRaw), depth != diffExplanationDepth {
            diffExplanationDepth = depth
        }
        if defaults.object(forKey: "zion.aiTransferSupportHints") != nil {
            let ath = defaults.bool(forKey: "zion.aiTransferSupportHints")
            if ath != aiTransferSupportHintsEnabled { aiTransferSupportHintsEnabled = ath }
        }

        // MARK: ntfy settings
        if let topic = defaults.string(forKey: "zion.ntfy.topic"), topic != ntfyTopic {
            ntfyTopic = topic
        }
        if let server = defaults.string(forKey: "zion.ntfy.serverURL"), !server.isEmpty, server != ntfyServerURL {
            ntfyServerURL = server
        }
        if let events = defaults.stringArray(forKey: "zion.ntfy.enabledEvents"), events != ntfyEnabledEvents {
            ntfyEnabledEvents = events
        }
        if defaults.object(forKey: "zion.ntfy.localNotifications") != nil {
            let nln = defaults.bool(forKey: "zion.ntfy.localNotifications")
            if nln != ntfyLocalNotificationsEnabled { ntfyLocalNotificationsEnabled = nln }
        }

        // MARK: File browser
        if defaults.object(forKey: "fileBrowser.showHiddenFiles") != nil {
            let sd = defaults.bool(forKey: "fileBrowser.showHiddenFiles")
            if sd != showDotfiles { showDotfiles = sd }
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

    // MARK: - Clone

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

    // MARK: - Recent Repositories

    func loadRecentRepositories() {
        if let urls = try? JSONDecoder().decode([URL].self, from: recentReposData) {
            let normalized = normalizeRecentRepositories(urls)
            recentRepositories = normalized
            if let encoded = try? JSONEncoder().encode(normalized) {
                recentReposData = encoded
            }
            refreshRecentWorktreeCounts()
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

    // MARK: - Gravatar Avatars

    func avatarImage(for email: String) -> NSImage? {
        guard !email.isEmpty else { return nil }
        let key = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let cached = avatarCache[key] { return cached }
        // Start download if not already in-flight
        if !avatarDownloadTasks.contains(key) {
            avatarDownloadTasks.insert(key)
            Task { [weak self] in
                guard let self else { return }
                let hash = Insecure.MD5.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
                guard let url = URL(string: "https://gravatar.com/avatar/\(hash)?s=40&d=identicon") else { return }
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if let image = NSImage(data: data) {
                        avatarCache[key] = image
                    }
                } catch {
                    // Silently fail — identicon fallback handled by Gravatar
                }
                avatarDownloadTasks.remove(key)
            }
        }
        return nil
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

    func detectGitHubRemote() -> GitHubRemote? {
        for remote in remotes {
            if let gh = GitHubClient.parseRemote(remote.url) {
                return gh
            }
        }
        return nil
    }

    // MARK: - Background Fetch

    func startBackgroundFetch() {
        backgroundFetchTask?.cancel()
        backgroundFetchTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000) // 60s
                if Task.isCancelled { break }
                if isSwitchingRepository { continue }
                await checkBehindRemote()
                await checkPRReviewRequests()
            }
        }
    }

    func checkBehindRemote() async {
        guard let url = repositoryURL else { return }
        if let suspendedUntil = autoFetchSuspendedUntil, suspendedUntil > Date() {
            return
        }

        do {
            // Dry-run fetch to check for updates
            let _ = try await worker.runAction(args: ["fetch", "--dry-run"], in: url)
            // Check how many commits behind
            let behindOutput = try await worker.runAction(
                args: ["rev-list", "--count", "HEAD..@{upstream}"],
                in: url
            )
            let newCount = Int(behindOutput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            behindRemoteCount = newCount
            // Check how many commits ahead
            let aheadOutput = try await worker.runAction(
                args: ["rev-list", "--count", "@{upstream}..HEAD"],
                in: url
            )
            aheadRemoteCount = Int(aheadOutput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            if newCount > 0 && lastNotifiedBehindCount == 0 {
                await ntfyClient.sendIfEnabled(
                    event: .newRemoteCommits,
                    title: L10n("ntfy.event.newRemoteCommits"),
                    body: "\(newCount) commits behind upstream",
                    repoName: url.lastPathComponent
                )
            }
            autoFetchCredentialFailures = 0
            autoFetchSuspendedUntil = nil
            lastNotifiedBehindCount = newCount
        } catch {
            if isCredentialFailure(error) {
                autoFetchCredentialFailures += 1
                let pauseMinutes = autoFetchCredentialFailures == 1 ? 10 : 30
                autoFetchSuspendedUntil = Date().addingTimeInterval(TimeInterval(pauseMinutes * 60))
                logger.log(
                    .warn,
                    "Auto-fetch paused after credential error (\(pauseMinutes)m)",
                    context: error.localizedDescription,
                    source: #function
                )
                return
            }

            if isNoUpstreamConfigured(error) {
                behindRemoteCount = 0
                aheadRemoteCount = 0
                lastNotifiedBehindCount = 0
                return
            }

            logger.log(.info, "Behind remote check failed (expected if no upstream): \(error.localizedDescription)", source: #function)
            behindRemoteCount = 0
            aheadRemoteCount = 0
            lastNotifiedBehindCount = 0
        }
    }

    func refreshPushDivergence(in repositoryURL: URL) async throws {
        let fetchArgs = ["fetch", "--all", "--prune"]
        let fetchSummary = redactedGitCommandSummary(args: fetchArgs)
        logger.log(.git, fetchSummary, context: "Push preflight")
        _ = try await runActionWithCredentialRetry(
            label: "Fetch",
            args: fetchArgs,
            in: repositoryURL,
            commandSummary: fetchSummary
        )

        do {
            let behindOutput = try await worker.runAction(
                args: ["rev-list", "--count", "HEAD..@{upstream}"],
                in: repositoryURL
            )
            behindRemoteCount = Int(behindOutput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

            let aheadOutput = try await worker.runAction(
                args: ["rev-list", "--count", "@{upstream}..HEAD"],
                in: repositoryURL
            )
            aheadRemoteCount = Int(aheadOutput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        } catch {
            if isNoUpstreamConfigured(error) {
                behindRemoteCount = 0
                aheadRemoteCount = 0
                return
            }
            throw error
        }
    }

    func isCredentialFailure(_ error: Error) -> Bool {
        guard case let GitClientError.commandFailed(_, message) = error else {
            return false
        }
        let lower = message.lowercased()
        return lower.contains("authentication failed")
            || lower.contains("could not read username")
            || lower.contains("could not read password")
            || lower.contains("terminal prompts disabled")
            || lower.contains("device not configured")
            || lower.contains("credential")
            || lower.contains("keychain")
            || lower.contains("git-credential-osxkeychain")
            || lower.contains("dev.azure.com")
    }

    func isNoUpstreamConfigured(_ error: Error) -> Bool {
        guard case let GitClientError.commandFailed(_, message) = error else {
            return false
        }
        return message.lowercased().contains("no upstream configured")
    }

    func checkPRReviewRequests() async {
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

    func startBackgroundMonitor(for url: URL) {
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

    func updateChangedFileCount(for url: URL) async {
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

    static func languageName(for ext: String) -> String {
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

    // MARK: - Auto Refresh Timer

    func startAutoRefreshTimer() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task {
            while !Task.isCancelled {
                // Wait for 30 seconds
                try? await Task.sleep(nanoseconds: 30_000_000_000)

                if Task.isCancelled { break }

                if isSwitchingRepository { continue }

                // Refresh without showing busy indicator to avoid UI flickering
                refreshRepository(setBusy: false, origin: .autoTimer)
            }
        }
    }

    // MARK: - PR Polling Timer

    func startPRPollingTimer() {
        prPollingTimer?.cancel()
        prPollingTimer = Task {
            while !Task.isCancelled {
                // Poll every 5 minutes
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
                if Task.isCancelled { break }
                if isSwitchingRepository { continue }
                refreshPRReviewQueue()
            }
        }
    }
}
