import Foundation
import SwiftUI

extension RepositoryViewModel {

    // MARK: - AI Pending Changes Summary

    func summarizePendingChanges() {
        guard let url = repositoryURL, isAIConfigured, !uncommittedChanges.isEmpty else { return }
        pendingSummaryTask?.cancel()
        isLoadingPendingChangesSummary = true
        aiPendingChangesSummary = ""

        let fileList = uncommittedChanges.joined(separator: "\n")
        pendingSummaryTask = Task { [weak self] in
            guard let self else { return }
            do {
                let diffStat = try await worker.runGitCommand(in: url, args: ["diff", "--stat"])
                try Task.checkCancellation()
                let summary = try await aiClient.summarizePendingChanges(
                    diffStat: diffStat,
                    fileList: fileList,
                    provider: aiProvider,
                    apiKey: aiAPIKey
                )
                try Task.checkCancellation()
                aiPendingChangesSummary = summary
                isLoadingPendingChangesSummary = false
            } catch {
                isLoadingPendingChangesSummary = false
                logger.log(.error, "AI pending changes summary failed: \(error.localizedDescription)", context: aiProvider.rawValue, source: #function)
            }
        }
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
                            let untrackedFiles = status
                                .split(separator: "\n")
                                .compactMap { RepositoryViewModel.parsePorcelainStatusLine(String($0)) }
                                .filter(\.isUntracked)
                                .map(\.path)

                            for file in untrackedFiles.prefix(Constants.Limits.maxUntrackedFilesForContext) {
                                if let content = try? await worker.runAction(args: ["show", ":\(file)"], in: url) {
                                    untrackedContext += "--- \(file) ---\n\(content.prefix(Constants.Limits.maxFileContentPreviewLength))\n"
                                } else if let localContent = try? String(contentsOf: url.appendingPathComponent(file), encoding: .utf8) {
                                    untrackedContext += "--- \(file) ---\n\(localContent.prefix(Constants.Limits.maxFileContentPreviewLength))\n"
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

                    let logOutput = try? await worker.runAction(args: ["log", "--oneline", "-10"], in: url)
                    let recentMessages = (logOutput ?? "").split(separator: "\n").map { line in
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
                } else if let aiErr = error as? AIError, case .temporarilyUnavailable = aiErr {
                    statusMessage = L10n("IA temporariamente indisponivel. Sugestao local aplicada.")
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

    func suggestPRDescription(baseBranch: String) async -> (title: String, body: String)? {
        guard let url = repositoryURL, isAIConfigured else { return nil }

        isGeneratingAIMessage = true
        defer { isGeneratingAIMessage = false }

        do {
            logger.log(.ai, "Requesting PR description", context: aiProvider.rawValue)
            let commitLog = try await worker.runAction(
                args: ["log", "--oneline", "\(baseBranch)..HEAD"],
                in: url
            )
            let diffStat = try await worker.runAction(
                args: ["diff", "--stat", "\(baseBranch)..HEAD"],
                in: url
            )
            let result = try await aiClient.generatePRDescription(
                commitLog: commitLog,
                diffStat: diffStat,
                branchName: currentBranch,
                baseBranch: baseBranch,
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
        let sourceRef = source.clean
        let targetRef = target.clean
        guard !sourceRef.isEmpty, !targetRef.isEmpty else { return }
        guard sourceRef != targetRef else {
            statusMessage = L10n("codereview.sameBranch.error")
            return
        }

        codeReviewTask?.cancel()
        codeReviewTask = Task {
            isCodeReviewLoading = true
            isCodeReviewVisible = true
            codeReviewFiles = []

            // Get diff stat for file list
            let diffStatResult = try? git.run(args: ["diff", "--numstat", "\(targetRef)...\(sourceRef)"], in: url)
            let diffStat = diffStatResult?.stdout ?? ""
            let files = parseDiffStatForCodeReview(diffStat, source: sourceRef, target: targetRef, at: url)
            codeReviewFiles = files
            if let first = files.first { selectedReviewFileID = first.id }

            // Get commit count
            let logCountResult = try? git.run(args: ["rev-list", "--count", "\(targetRef)...\(sourceRef)"], in: url)
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

    func parseDiffStatForCodeReview(_ output: String, source: String, target: String, at url: URL) -> [CodeReviewFile] {
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

    func recalculateCodeReviewStats(commitCount: Int) {
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

    func openPRFromInfo(_ pr: GitHubPRInfo) {
        branchReviewSource = pr.headBranch
        branchReviewTarget = pr.baseBranch
        if !pr.headBranch.isEmpty && !pr.baseBranch.isEmpty {
            startCodeReview(source: pr.headBranch, target: pr.baseBranch)
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
                        title: "PR #\(item.pr.number) reviewed",
                        body: buildReviewNotificationBody(prTitle: item.pr.title, findings: findings),
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
            aiConflictResolvingRegionID = region.id
            defer {
                isGeneratingAIMessage = false
                aiConflictResolvingRegionID = nil
            }

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
                aiConflictResolutionRegionID = region.id
                aiConflictResolution = resolved
            } catch {
                logger.log(.error, "AI conflict resolution failed: \(error.localizedDescription)", context: aiProvider.rawValue, source: #function)
                aiConflictResolutionRegionID = nil
                aiConflictResolution = ""
                lastError = error.localizedDescription
            }
        }
    }

    func consumeAIConflictResolution(for regionID: UUID) -> String? {
        guard aiConflictResolutionRegionID == regionID, !aiConflictResolution.isEmpty else { return nil }
        let resolved = aiConflictResolution
        aiConflictResolution = ""
        aiConflictResolutionRegionID = nil
        return resolved
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

    func cachedReviewFindings(for commitID: String) -> [ReviewFinding]? {
        commitReviewCache[commitID]
    }

    func clearCommitReviewSelectionStateOnCommitChange() {
        selectedCommitDetailTab = .details
    }

    func reviewCommitChanges(commitID: String) {
        guard let url = repositoryURL, isAIConfigured else { return }

        aiTask?.cancel()
        reviewingCommitID = commitID

        aiTask = Task {
            isGeneratingAIMessage = true
            defer {
                isGeneratingAIMessage = false
                if reviewingCommitID == commitID {
                    reviewingCommitID = nil
                }
            }

            do {
                logger.log(.ai, "Requesting commit review", context: "\(aiProvider.rawValue): \(commitID)")

                var diff: String = ""
                var diffStat: String = ""

                do {
                    diff = try await worker.runAction(args: ["diff", "\(commitID)~1", commitID], in: url)
                    diffStat = try await worker.runAction(args: ["diff", "--stat", "\(commitID)~1", commitID], in: url)
                } catch {
                    // Root commit or missing parent: fallback to commit patch output.
                    diff = try await worker.runAction(args: ["show", "--format=", "--patch", commitID], in: url)
                    diffStat = try await worker.runAction(args: ["show", "--format=", "--stat", commitID], in: url)
                }

                guard !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    let findings = [ReviewFinding(
                        severity: .suggestion,
                        file: "general",
                        message: L10n("graph.commit.review.nodiff")
                    )]
                    commitReviewCache[commitID] = findings
                    aiReviewFindings = findings
                    isReviewVisible = true
                    if selectedCommitID == commitID {
                        selectedCommitDetailTab = .aiReview
                    }
                    return
                }

                let findings = try await aiClient.reviewDiff(
                    diff: diff,
                    diffStat: diffStat,
                    branchName: currentBranch,
                    provider: aiProvider,
                    apiKey: aiAPIKey
                )

                logger.log(.ai, "Commit review generated OK: \(findings.count) findings", context: commitID)
                commitReviewCache[commitID] = findings
                aiReviewFindings = findings
                isReviewVisible = true
                if selectedCommitID == commitID {
                    selectedCommitDetailTab = .aiReview
                }
            } catch {
                if let aiErr = error as? AIError, case .quotaExceeded = aiErr {
                    aiQuotaExceeded = true
                }
                logger.log(.error, "AI commit review failed: \(error.localizedDescription)", context: aiProvider.rawValue, source: #function)
                lastError = error.localizedDescription
            }
        }
    }

    // MARK: - Pre-Commit AI Review Gate

    func runPreCommitReview() {
        guard let url = repositoryURL, isAIConfigured, preCommitReviewEnabled else {
            preCommitReviewPending = false
            return
        }

        aiTask?.cancel()
        preCommitReviewPending = true
        aiTask = Task {
            isGeneratingAIMessage = true
            defer { isGeneratingAIMessage = false }

            do {
                let diff = try await worker.runAction(args: ["diff", "--cached"], in: url)
                let diffHash = String(diff.hashValue)

                // Use cache if diff unchanged
                if diffHash == preCommitDiffHash && !aiReviewFindings.isEmpty {
                    isReviewVisible = true
                    return
                }

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
                logger.log(.ai, "Pre-commit review: \(findings.count) findings")
                aiReviewFindings = findings
                isReviewVisible = true
                preCommitDiffHash = diffHash
            } catch {
                if let aiErr = error as? AIError, case .quotaExceeded = aiErr {
                    aiQuotaExceeded = true
                }
                logger.log(.error, "Pre-commit review failed: \(error.localizedDescription)", context: aiProvider.rawValue, source: #function)
                lastError = error.localizedDescription
                preCommitReviewPending = false
            }
        }
    }

    func dismissPreCommitReview() {
        preCommitReviewPending = false
        isReviewVisible = false
    }

    var preCommitHasCritical: Bool {
        aiReviewFindings.contains { $0.severity == .critical }
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

    // MARK: - Heuristic Commit Message

    static func generateCommitMessage(diffStat: String, status: String) -> String {
        let lines = status.split(separator: "\n").map(String.init)
        guard !lines.isEmpty else { return "" }

        var added = 0, modified = 0, deleted = 0
        var paths: [String] = []
        for line in lines {
            guard let entry = RepositoryViewModel.parsePorcelainStatusLine(line) else { continue }
            let indexStatus = entry.indexStatus
            let workTreeStatus = entry.worktreeStatus
            let file = entry.path

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

    // MARK: - Notification Helpers

    private func buildReviewNotificationBody(prTitle: String, findings: [ReviewFinding]) -> String {
        if findings.isEmpty {
            return "\(prTitle) — clean, no issues found"
        }
        var lines = ["\(prTitle) — \(findings.count) finding\(findings.count == 1 ? "" : "s")"]
        for f in findings.prefix(3) {
            let icon = f.severity == .critical ? "🔴" : f.severity == .warning ? "🟡" : "🔵"
            let file = f.file.split(separator: "/").last.map(String.init) ?? f.file
            lines.append("\(icon) \(file): \(f.message.prefix(60))")
        }
        if findings.count > 3 {
            lines.append("… and \(findings.count - 3) more")
        }
        return lines.joined(separator: "\n")
    }
}
