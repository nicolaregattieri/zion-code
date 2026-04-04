import Foundation
import SwiftUI
import CryptoKit

extension RepositoryViewModel {

    // MARK: - Git Hosting Provider Integration

    func loadPullRequests() {
        prTask?.cancel()
        prTask = Task { [weak self] in
            guard let self else { return }
            _ = await self.refreshPullRequestsCatalog(notifyOnNewPRs: false)
        }
    }

    @discardableResult
    func refreshPullRequestsCatalog(notifyOnNewPRs: Bool) async -> [HostedPRInfo] {
        guard let repositoryURL,
              let (provider, remote) = detectHostingProvider() else { return [] }
        hostingProvider = provider

        let requestToken = UUID()
        pullRequestLoadToken = requestToken

        let prs = await provider.fetchPullRequests(remote: remote)
        guard !Task.isCancelled else { return [] }
        guard pullRequestLoadToken == requestToken, self.repositoryURL == repositoryURL else { return [] }

        let transition = Self.openPRNotificationTransition(existingIDs: observedOpenPRIDs, activePRs: prs)

        // Phase 2B: Detect merged/closed PRs
        if let previousIDs = observedOpenPRIDs, notifyOnNewPRs {
            let currentIDs = transition.nextIDs
            let disappearedIDs = previousIDs.subtracting(currentIDs)
            if !disappearedIDs.isEmpty {
                let repoName = repositoryURL.lastPathComponent
                for disappearedID in disappearedIDs {
                    let title = previousPRTitles[disappearedID] ?? "#\(disappearedID)"
                    await ntfyClient.sendIfEnabled(
                        event: .prMergedOrClosed,
                        title: L10n("ntfy.prMergedClosed.title"),
                        body: L10n("ntfy.prMergedClosed.body", title),
                        repoName: repoName
                    )
                }
            }
        }

        // Cache current PR titles for merge/close detection
        for pr in prs {
            previousPRTitles[pr.id] = pr.title
        }

        observedOpenPRIDs = transition.nextIDs
        pullRequests = prs

        guard notifyOnNewPRs else { return prs }

        for pr in transition.newlyCreated {
            await notifyPRCreated(title: pr.title, url: pr.url)
        }

        return prs
    }

    func prForBranch(_ branch: String) -> HostedPRInfo? {
        pullRequests.first { $0.headBranch == branch }
    }

    var hasHostingProvider: Bool {
        detectHostingProvider() != nil
    }

    /// Legacy alias for backward compatibility.
    var hasGitHubRemote: Bool { hasHostingProvider }

    /// Detect which hosting provider matches the current remotes.
    /// Tries GitHub (via `gh` CLI), then GitLab, then Bitbucket.
    func detectHostingProvider() -> (provider: any GitHostingProvider, remote: HostedRemote)? {
        for remote in remotes {
            if let hosted = GitHubClient.parseRemote(remote.url) {
                return (githubClient, hosted)
            }
            if let hosted = GitLabClient.parseRemote(remote.url) {
                return (gitlabClient, hosted)
            }
            if let hosted = BitbucketClient.parseRemote(remote.url) {
                return (bitbucketClient, hosted)
            }
            if let hosted = AzureDevOpsClient.parseRemote(remote.url) {
                return (azureDevOpsClient, hosted)
            }
        }
        return nil
    }

    /// Detect the hosted remote for the current repository (without the provider reference).
    func detectHostedRemote() -> HostedRemote? {
        detectHostingProvider()?.remote
    }

    // MARK: - Background Fetch

    func startBackgroundFetch() {
        backgroundFetchTask?.cancel()
        backgroundFetchTask = Task {
            // Stagger: first behind-remote check after initial delay
            try? await Task.sleep(nanoseconds: Constants.Timing.behindRemoteCheckInitialDelay)
            if Task.isCancelled { return }
            if !isSwitchingRepository, NSApp.isActive {
                isBackgroundFetching = true
                await checkBehindRemote()
                isBackgroundFetching = false
            }
        }
    }

    /// Triggered by NSApp.didBecomeActiveNotification to refresh behind/ahead badges.
    /// Uses a cooldown to avoid hammering on rapid app switches.
    func refreshOnActivate() {
        guard repositoryURL != nil else { return }
        guard !isSwitchingRepository else { return }
        let elapsed = Date().timeIntervalSince(lastBehindRemoteCheckDate)
        guard elapsed >= Constants.Timing.behindRemoteCheckCooldown else { return }
        lastBehindRemoteCheckDate = Date()
        backgroundFetchTask?.cancel()
        backgroundFetchTask = Task {
            isBackgroundFetching = true
            await checkBehindRemote()
            isBackgroundFetching = false
        }
    }

    func checkBehindRemote() async {
        guard let url = repositoryURL else { return }
        if let suspendedUntil = autoFetchSuspendedUntil, suspendedUntil > Date() {
            return
        }
        if isBusy {
            return
        }

        let previousBehind = behindRemoteCount
        let previousAhead = aheadRemoteCount

        do {
            // Pre-check: compare local tracking ref with remote to avoid expensive fetch
            // when nothing has changed on the remote. (RT-003)
            let shouldFetch: Bool
            do {
                let trackingRef = try await worker.runAction(
                    args: ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
                    in: url
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                let localRef = try await worker.runAction(
                    args: ["rev-parse", trackingRef],
                    in: url
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                // Extract remote name and branch from "origin/main" format
                let parts = trackingRef.split(separator: "/", maxSplits: 1)
                if parts.count == 2 {
                    let remote = String(parts[0])
                    let branch = String(parts[1])
                    let lsOutput = try await worker.runAction(
                        args: ["ls-remote", "--heads", remote, "refs/heads/\(branch)"],
                        in: url
                    ).trimmingCharacters(in: .whitespacesAndNewlines)
                    let remoteHash = lsOutput.split(separator: "\t").first.map(String.init) ?? ""
                    shouldFetch = remoteHash != localRef
                } else {
                    shouldFetch = true
                }
            } catch {
                // No upstream configured or ls-remote failed -- always fetch as fallback
                shouldFetch = true
            }

            if shouldFetch {
                let _ = try await worker.runAction(args: ["fetch", "--all", "--prune"], in: url)
            }
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
            let newAheadCount = Int(aheadOutput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            aheadRemoteCount = newAheadCount
            if Self.shouldRefreshAfterRemoteDivergenceUpdate(
                previousBehind: previousBehind,
                previousAhead: previousAhead,
                newBehind: newCount,
                newAhead: newAheadCount
            ) {
                refreshRepository(setBusy: false, origin: .autoTimer)
            }
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
        }
    }

    static func shouldRefreshAfterRemoteDivergenceUpdate(
        previousBehind: Int,
        previousAhead: Int,
        newBehind: Int,
        newAhead: Int
    ) -> Bool {
        previousBehind != newBehind || previousAhead != newAhead
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
        guard let (provider, remote) = detectHostingProvider() else { return }
        let catalog = await ensurePRCatalogLoaded(provider: provider, remote: remote)
        let prs = await provider.fetchPRsRequestingMyReview(remote: remote)
        let enrichedPRs = prs.map { Self.enrichedReviewRequestPR($0, catalog: catalog) }
        let transition = Self.reviewRequestNotificationTransition(
            existingIDs: notifiedReviewRequestPRIDs,
            activePRs: enrichedPRs
        )
        notifiedReviewRequestPRIDs = transition.nextIDs

        for pr in transition.newlyRequested {
            let files = await provider.fetchPRFiles(remote: remote, prNumber: pr.number)
            let repoContext = buildRepoContext(
                fileHints: Self.reviewRequestFileHints(from: files),
                extraNotes: Self.reviewRequestExtraNotes(pr: pr, files: files)
            )
            await ntfyClient.sendIfEnabled(
                event: .prReviewRequested,
                title: L10n("ntfy.event.prReviewRequested"),
                body: Self.buildReviewRequestNotificationBody(pr: pr, repoContext: repoContext),
                repoName: repositoryURL?.lastPathComponent ?? ""
            )
        }
    }

    // MARK: - PR Polling Timer

    func startPRPollingTimer() {
        prPollingTimer?.cancel()
        prPollingTimer = Task {
            // Stagger: PR polling is lowest priority, delayed to avoid overlap with other timers.
            try? await Task.sleep(nanoseconds: Constants.Timing.prPollingInitialDelay)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.prPollingIntervalNanoseconds(for: prPollingIntervalMinutes))
                if Task.isCancelled { break }
                if isSwitchingRepository { continue }
                guard NSApp.isActive else { continue }
                await refreshPullRequestsCatalog(notifyOnNewPRs: true)
                refreshPRReviewQueue()
            }
        }
    }

    static func sanitizedPRPollingIntervalMinutes(_ minutes: Int) -> Int {
        let allowed = [2, 5, 10, 30]
        return allowed.contains(minutes) ? minutes : 5
    }

    static func prPollingIntervalNanoseconds(for minutes: Int) -> UInt64 {
        UInt64(sanitizedPRPollingIntervalMinutes(minutes)) * 60 * 1_000_000_000
    }

    // MARK: - Credential Retry

    private func isTransientNetworkError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("could not resolve host")
            || message.contains("connection refused")
            || message.contains("connection reset")
            || message.contains("network is unreachable")
            || message.contains("timed out")
            || message.contains("ssl")
            || message.contains("temporary failure")
    }

    private func isNetworkCommand(_ args: [String]) -> Bool {
        guard let subcommand = args.first?.lowercased() else { return false }
        return subcommand == "push"
            || subcommand == "pull"
            || subcommand == "fetch"
            || subcommand == "clone"
    }

    func runActionWithCredentialRetry(
        label: String,
        args: [String],
        in repositoryURL: URL,
        commandSummary: String
    ) async throws -> String {
        do {
            return try await worker.runAction(args: args, in: repositoryURL)
        } catch {
            // Retry once for transient network errors on network commands
            if isNetworkCommand(args), isTransientNetworkError(error) {
                logger.log(.warn, "Transient network error, retrying…", context: commandSummary)
                try await Task.sleep(nanoseconds: Constants.Timing.networkRetryDelay)
                do {
                    return try await worker.runAction(args: args, in: repositoryURL)
                } catch {
                    // Fall through to credential retry logic below
                }
            }

            guard shouldHandleCredentialPrompt(for: args),
                  isCredentialFailure(error),
                  let context = buildGitAuthContext(
                    label: label,
                    args: args,
                    commandSummary: commandSummary,
                    error: error
                  ) else {
                throw error
            }

            if let stored = gitCredentialStore.load(host: context.host, usernameHint: context.usernameHint) {
                do {
                    return try await worker.runAction(
                        args: args,
                        in: repositoryURL,
                        mode: .withCredential(GitCredentialInput(username: stored.username, secret: stored.secret))
                    )
                } catch {
                    if isCredentialFailure(error) {
                        try? gitCredentialStore.delete(host: context.host, username: stored.username)
                    } else {
                        throw error
                    }
                }
            }

            let promptResult = await requestGitCredentials(context: context)
            switch promptResult {
            case .cancelled:
                throw GitClientError.commandFailed(command: commandSummary, message: L10n("git.auth.cancelled"))
            case .provided(let usernameRaw, let secretRaw):
                let secret = secretRaw.clean
                guard !secret.isEmpty else {
                    throw GitClientError.commandFailed(command: commandSummary, message: L10n("git.auth.secretRequired"))
                }

                let normalizedUsername = usernameRaw.clean
                let effectiveUsername = normalizedUsername.isEmpty ? context.usernameHint : normalizedUsername
                let credential = GitCredentialInput(username: effectiveUsername, secret: secret)
                let output = try await worker.runAction(args: args, in: repositoryURL, mode: .withCredential(credential))

                if let effectiveUsername, !effectiveUsername.isEmpty {
                    try? gitCredentialStore.save(host: context.host, username: effectiveUsername, secret: secret)
                }
                return output
            }
        }
    }

    func shouldHandleCredentialPrompt(for args: [String]) -> Bool {
        guard let subcommand = args.first?.lowercased() else { return false }
        return subcommand == "fetch"
            || subcommand == "pull"
            || subcommand == "push"
            || subcommand == "ls-remote"
    }

    func buildGitAuthContext(
        label: String,
        args: [String],
        commandSummary: String,
        error: Error
    ) -> GitAuthContext? {
        guard let remoteURL = resolveRemoteURL(for: args),
              let remote = parseHTTPSRemote(remoteURL) else {
            return nil
        }

        let message: String
        if case let GitClientError.commandFailed(_, m) = error {
            message = m
        } else {
            message = error.localizedDescription
        }

        return GitAuthContext(
            operationLabel: label,
            commandSummary: commandSummary,
            remoteURL: remoteURL,
            host: remote.host,
            usernameHint: remote.usernameHint,
            errorMessage: message,
            isAzureDevOps: remote.host.contains("dev.azure.com")
        )
    }

    func resolveRemoteURL(for args: [String]) -> String? {
        guard !remotes.isEmpty else { return nil }
        let remoteMap = Dictionary(uniqueKeysWithValues: remotes.map { ($0.name, $0.url) })

        let nonOptionTokens = args.filter { !$0.hasPrefix("-") }
        for token in nonOptionTokens.reversed() {
            if let url = remoteMap[token] {
                return url
            }
        }
        return remotes.first?.url
    }

    func parseHTTPSRemote(_ remoteURL: String) -> (host: String, usernameHint: String?)? {
        guard let components = URLComponents(string: remoteURL),
              let scheme = components.scheme?.lowercased(),
              scheme == "https",
              let host = components.host?.lowercased() else {
            return nil
        }

        let user = components.user?.clean
        return (host, user?.isEmpty == true ? nil : user)
    }

    func requestGitCredentials(context: GitAuthContext) async -> GitAuthPromptResult {
        if let existing = gitAuthPromptContinuation {
            gitAuthPromptContinuation = nil
            existing.resume(returning: .cancelled)
        }
        gitAuthContext = context
        isGitAuthPromptVisible = true
        return await withCheckedContinuation { continuation in
            gitAuthPromptContinuation = continuation
        }
    }

    func submitGitAuthPrompt(username: String, secret: String) {
        guard let continuation = gitAuthPromptContinuation else { return }
        gitAuthPromptContinuation = nil
        isGitAuthPromptVisible = false
        gitAuthContext = nil
        continuation.resume(returning: .provided(username: username, secret: secret))
    }

    func cancelGitAuthPrompt() {
        guard let continuation = gitAuthPromptContinuation else { return }
        gitAuthPromptContinuation = nil
        isGitAuthPromptVisible = false
        gitAuthContext = nil
        continuation.resume(returning: .cancelled)
    }

    func redactedGitCommandSummary(args: [String]) -> String {
        let subcommand = args.first ?? "command"
        let fingerprint = gitArgsFingerprint(args)
        return "git \(subcommand) [args=\(args.count), id=\(fingerprint)]"
    }

    func gitArgsFingerprint(_ args: [String]) -> String {
        let payload = args.joined(separator: "\u{1f}")
        let digest = SHA256.hash(data: Data(payload.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(10))
    }

}
