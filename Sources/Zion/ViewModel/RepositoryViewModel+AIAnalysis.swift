import Foundation

extension RepositoryViewModel {

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
                    apiKey: aiAPIKey,
                    mode: aiMode
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
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            resetSemanticSearchResults()
            return
        }

        aiTask?.cancel()
        aiTask = Task {
            isGeneratingAIMessage = true
            defer { isGeneratingAIMessage = false }

            do {
                logger.log(.ai, "Requesting semantic search", context: "\(aiProvider.rawValue): \(trimmedQuery)")
                let historyOutput = try await worker.runAction(
                    args: [
                        "log",
                        "-n", "80",
                        "--date=short",
                        "--format=%H%x1f%h%x1f%an%x1f%ad%x1f%s%x1e",
                        "--name-only",
                    ],
                    in: url
                )
                try Task.checkCancellation()
                let candidates = Self.parseHistorySearchCandidates(from: historyOutput)
                let rankedCandidates = Self.rankHistorySearchCandidates(candidates, query: trimmedQuery, limit: 18)
                let result = try await aiClient.searchCommitHistory(
                    query: trimmedQuery,
                    candidates: rankedCandidates,
                    provider: aiProvider,
                    apiKey: aiAPIKey,
                    mode: aiMode
                )
                try Task.checkCancellation()
                let answer = result.answer.isEmpty
                    ? (result.matches.isEmpty ? L10n("graph.ai.noMatches") : L10n("graph.ai.answerFallback"))
                    : result.answer
                logger.log(.ai, "Semantic search OK: \(result.matches.count) results")
                aiHistorySearchResult = AIHistorySearchResult(answer: answer, matches: result.matches)
            } catch {
                if error is CancellationError {
                    return
                }
                if let aiErr = error as? AIError, case .quotaExceeded = aiErr {
                    aiQuotaExceeded = true
                }
                logger.log(.error, "AI semantic search failed: \(error.localizedDescription)", context: aiProvider.rawValue, source: #function)
                aiHistorySearchResult = nil
                lastError = error.localizedDescription
            }
        }
    }

    func resetSemanticSearchResults() {
        aiTask?.cancel()
        aiHistorySearchResult = nil
    }

    func clearSemanticSearch() {
        resetSemanticSearchResults()
        isSemanticSearchActive = false
    }

    static func parseHistorySearchCandidates(from raw: String) -> [AIHistorySearchCandidate] {
        raw.components(separatedBy: "\u{1e}").compactMap { chunk in
            let trimmedChunk = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedChunk.isEmpty else { return nil }

            let lines = trimmedChunk
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard let metadataLine = lines.first else { return nil }
            let metadata = metadataLine.split(separator: "\u{1f}", maxSplits: 4).map(String.init)
            guard metadata.count == 5 else { return nil }

            return AIHistorySearchCandidate(
                fullHash: metadata[0],
                shortHash: metadata[1],
                subject: metadata[4],
                author: metadata[2],
                dateText: metadata[3],
                files: Array(lines.dropFirst())
            )
        }
    }

    static func rankHistorySearchCandidates(
        _ candidates: [AIHistorySearchCandidate],
        query: String,
        limit: Int = 18
    ) -> [AIHistorySearchCandidate] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return Array(candidates.prefix(limit)) }

        let queryTerms = historySearchTerms(from: trimmedQuery)
        let loweredQuery = trimmedQuery.lowercased()
        let ranked = candidates.enumerated().map { index, candidate in
            let subject = candidate.subject.lowercased()
            let author = candidate.author.lowercased()
            let hash = candidate.shortHash.lowercased()
            let fullHash = candidate.fullHash.lowercased()
            let files = candidate.files.map { $0.lowercased() }

            var score = 0
            if subject.contains(loweredQuery) { score += 8 }
            if author.contains(loweredQuery) { score += 4 }
            if files.contains(where: { $0.contains(loweredQuery) }) { score += 10 }
            if hash.hasPrefix(loweredQuery) || fullHash.hasPrefix(loweredQuery) { score += 12 }

            for term in queryTerms {
                if subject.contains(term) { score += 3 }
                if author.contains(term) { score += 2 }
                if files.contains(where: { $0.contains(term) }) { score += 4 }
                if hash.hasPrefix(term) || fullHash.hasPrefix(term) { score += 6 }
            }

            return (candidate: candidate, score: score, index: index)
        }

        let sorted = ranked.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.index < rhs.index
            }
            return lhs.score > rhs.score
        }

        let positiveMatches = sorted.filter { $0.score > 0 }
        if positiveMatches.count >= min(limit, 5) {
            return Array(positiveMatches.prefix(limit).map(\.candidate))
        }

        let prefix = Array(positiveMatches.prefix(limit).map(\.candidate))
        let prefixHashes = Set(prefix.map(\.fullHash))
        let remainder = candidates.filter { candidate in
            !prefixHashes.contains(candidate.fullHash)
        }

        return Array((prefix + remainder).prefix(limit))
    }

    static func historySearchTerms(from query: String) -> [String] {
        let normalized = query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
        var seen = Set<String>()
        return normalized.filter { seen.insert($0).inserted }
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
                    apiKey: aiAPIKey,
                    mode: aiMode
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
                    apiKey: aiAPIKey,
                    mode: aiMode,
                    repoContext: buildRepoContext(
                        fileHints: Self.parseFileHints(fromDiffStat: diffStat),
                        extraNotes: [
                            "source branch: \(source)",
                            "target branch: \(target)"
                        ]
                    )
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
                    apiKey: aiAPIKey,
                    mode: aiMode,
                    repoContext: buildRepoContext(
                        fileHints: [fileName],
                        extraNotes: ["commit subject: \(commitSubject)"]
                    )
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
                    apiKey: aiAPIKey,
                    mode: aiMode,
                    repoContext: buildRepoContext(fileHints: Self.parseFileHints(fromDiffStat: diffStat))
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
}
