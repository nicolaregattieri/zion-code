import Foundation
import SwiftUI

extension RepositoryViewModel {

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
                        apiKey: aiAPIKey,
                        mode: aiMode,
                        repoContext: buildRepoContext(fileHints: [codeReviewFiles[i].path])
                    )
                    codeReviewFiles[i].findings = findings
                    codeReviewFiles[i].isReviewed = true

                    // Also get detailed explanation
                    let explanation = try await aiClient.explainDiffDetailed(
                        fileDiff: codeReviewFiles[i].diff,
                        fileName: codeReviewFiles[i].path,
                        provider: aiProvider,
                        apiKey: aiAPIKey,
                        mode: aiMode,
                        repoContext: buildRepoContext(fileHints: [codeReviewFiles[i].path])
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
                if let evidence = finding.evidence {
                    summary += "  evidence: \(evidence)\n"
                }
                if let testImpact = finding.testImpact {
                    summary += "  test impact: \(testImpact)\n"
                }
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
                    if let evidence = finding.evidence {
                        md += "  - Evidence: \(evidence)\n"
                    }
                    if let testImpact = finding.testImpact {
                        md += "  - Test Impact: \(testImpact)\n"
                    }
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
        let resolvedPR = Self.enrichedReviewRequestPR(item.pr, catalog: pullRequests)
        branchReviewSource = resolvedPR.headBranch
        branchReviewTarget = resolvedPR.baseBranch
        if !resolvedPR.headBranch.isEmpty && !resolvedPR.baseBranch.isEmpty {
            startCodeReview(source: resolvedPR.headBranch, target: resolvedPR.baseBranch)
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
        guard isAIConfigured,
              let url = repositoryURL,
              let (provider, remote) = detectHostingProvider() else { return }

        for i in prReviewQueue.indices where prReviewQueue[i].status == .pending {
            prReviewQueue[i].status = .reviewing

            let item = prReviewQueue[i]
            let idx = i
            Task {
                do {
                    let resolvedPR = Self.enrichedReviewRequestPR(item.pr, catalog: pullRequests)
                    let diffPayload = await reviewDiffPayload(for: resolvedPR, provider: provider, remote: remote, repositoryURL: url)
                    guard !diffPayload.diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        prReviewQueue[idx].status = .pending
                        return
                    }
                    let fileHints = diffPayload.diffStat.isEmpty ? [] : Self.parseFileHints(fromDiffStat: diffPayload.diffStat)
                    let repoContext = buildRepoContext(
                        fileHints: fileHints,
                        extraNotes: [
                            "source branch: \(resolvedPR.headBranch)",
                            "target branch: \(resolvedPR.baseBranch)",
                            "pr title: \(resolvedPR.title)",
                            "author: \(resolvedPR.author)"
                        ]
                    )
                    let findings = try await aiClient.reviewBranch(
                        diff: diffPayload.diff,
                        diffStat: diffPayload.diffStat,
                        sourceBranch: resolvedPR.headBranch.isEmpty ? "PR #\(resolvedPR.number)" : resolvedPR.headBranch,
                        targetBranch: resolvedPR.baseBranch.isEmpty ? "review target" : resolvedPR.baseBranch,
                        provider: aiProvider,
                        apiKey: aiAPIKey,
                        mode: aiMode,
                        repoContext: repoContext
                    )

                    prReviewQueue[idx].findings = findings
                    prReviewQueue[idx].status = findings.contains(where: { $0.severity == .critical || $0.severity == .warning }) ? .reviewed : .clean
                    prReviewQueue[idx].reviewedAt = Date()

                    // Notify
                    let repoName = url.lastPathComponent
                    await ntfyClient.sendIfEnabled(
                        event: .prAutoReviewComplete,
                        title: "PR #\(resolvedPR.number) reviewed",
                        body: Self.buildReviewNotificationBody(
                            pr: resolvedPR,
                            findings: findings,
                            repoContext: repoContext
                        ),
                        repoName: repoName
                    )
                } catch {
                    prReviewQueue[idx].status = .pending
                }
            }
        }
    }

    func refreshPRReviewQueue() {
        guard repositoryURL != nil,
              let (provider, remote) = detectHostingProvider() else { return }

        prPollingTask?.cancel()
        prPollingTask = Task {
            let openPRCatalog = await ensurePRCatalogLoaded(provider: provider, remote: remote)
            let prs = await provider.fetchPRsRequestingMyReview(remote: remote)
            let enrichedPRs = prs.map { Self.enrichedReviewRequestPR($0, catalog: openPRCatalog) }
            let existingItems = Dictionary(uniqueKeysWithValues: prReviewQueue.map { ($0.pr.id, $0) })

            prReviewQueue = enrichedPRs.map { pr in
                if let existing = existingItems[pr.id] {
                    return PRReviewItem(
                        pr: pr,
                        status: existing.status,
                        findings: existing.findings,
                        reviewedAt: existing.reviewedAt
                    )
                }
                return PRReviewItem(pr: pr)
            }

            // Auto-review if enabled
            let autoReview = UserDefaults.standard.bool(forKey: "zion.autoReviewAssignedPRs")
            if autoReview && isAIConfigured {
                reviewAllPRs()
            }
        }
    }

    // MARK: - AI Code Review (Staged & Commit)

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
                    apiKey: aiAPIKey,
                    mode: aiMode,
                    repoContext: buildRepoContext(fileHints: Self.parseFileHints(fromDiffStat: diffStat))
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
                    apiKey: aiAPIKey,
                    mode: aiMode,
                    repoContext: buildRepoContext(fileHints: Self.parseFileHints(fromDiffStat: diffStat))
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
                    apiKey: aiAPIKey,
                    mode: aiMode,
                    repoContext: buildRepoContext(fileHints: Self.parseFileHints(fromDiffStat: diffStat))
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
}
