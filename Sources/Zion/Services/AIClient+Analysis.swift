import Foundation

// MARK: - History Analysis & Generation

extension AIClient {

    // MARK: - Changelog Generator

    func generateChangelog(
        commitLog: String,
        fromRef: String,
        toRef: String,
        provider: AIProvider,
        apiKey: String,
        mode: AIMode
    ) async throws -> String {
        let payload = Self.makePromptPayload(
            task: "Generate release notes",
            taskInstructions: """
            Create a categorized changelog from the provided commit log.

            Output format (markdown):
        ## What's New

        ### Features
        - description

        ### Bug Fixes
        - description

        ### Improvements
        - description

        ### Breaking Changes
        - description (only if applicable)

        Rules:
        - Group commits by category
        - Write user-facing descriptions, not commit messages
        - Omit empty categories
        - Be concise but informative
        - Output ONLY the markdown, nothing else
        """,
            untrustedSections: [
                AIUntrustedPromptSection(
                    kind: "from_ref",
                    label: "From ref",
                    content: fromRef,
                    maxLength: 120
                ),
                AIUntrustedPromptSection(
                    kind: "to_ref",
                    label: "To ref",
                    content: toRef,
                    maxLength: 120
                ),
                AIUntrustedPromptSection(
                    kind: "commit_log",
                    label: "Commits",
                    content: commitLog,
                    maxLength: AILimits.maxChangelogLogLength
                ),
            ]
        )
        return try await call(payload: payload, provider: provider, apiKey: apiKey, maxTokens: AILimits.changelogTokens, lane: .general, mode: mode)
    }

    // MARK: - Semantic Search

    func searchCommitHistory(
        query: String,
        candidates: [AIHistorySearchCandidate],
        provider: AIProvider,
        apiKey: String,
        mode: AIMode
    ) async throws -> AIHistorySearchResult {
        guard !candidates.isEmpty else {
            return AIHistorySearchResult(answer: "", matches: [])
        }
        let commitLog = Self.makeHistorySearchContext(from: candidates)
        let payload = Self.makePromptPayload(
            task: "Answer a question about git history",
            taskInstructions: """
            The user is asking this question about recent commit history:
            "\(Self.sanitizePromptSegment(query))"

            Output format (exactly):
        ANSWER: <one short sentence answering the query>
        MATCH: <short hash> | <brief reason>

        Rules:
        - Use ONLY hashes from the candidate list
        - Return 0 to 5 MATCH lines
        - Keep the answer under 140 characters
        - Each reason should mention the strongest evidence, such as files, subject, or author
        - If nothing looks relevant, still provide an ANSWER and then output: MATCH: NONE
        - Output ONLY the ANSWER and MATCH lines, nothing else
        """,
            untrustedSections: [
                AIUntrustedPromptSection(
                    kind: "candidate_commits",
                    label: "Candidate commits",
                    content: commitLog,
                    maxLength: AILimits.maxSemanticSearchLogLength
                ),
            ]
        )
        let raw = try await call(payload: payload, provider: provider, apiKey: apiKey, maxTokens: AILimits.semanticSearchTokens, lane: .general, mode: mode)
        let parsed = Self.parseHistorySearchResponse(raw)
        let allowedHashes = Set(candidates.map { $0.shortHash.lowercased() })
        var seen = Set<String>()
        let filteredMatches = parsed.matches.filter { match in
            let normalizedHash = match.hash.lowercased()
            guard allowedHashes.contains(normalizedHash) else { return false }
            return seen.insert(normalizedHash).inserted
        }
        return AIHistorySearchResult(answer: parsed.answer, matches: filteredMatches)
    }

    // MARK: - Branch Summarizer

    func summarizeBranch(
        branchName: String,
        commitLog: String,
        diffStat: String,
        provider: AIProvider,
        apiKey: String,
        mode: AIMode
    ) async throws -> String {
        let payload = Self.makePromptPayload(
            task: "Summarize a branch",
            taskInstructions: """
            Write a single-sentence summary of what this branch does.

            Rules:
        - Output EXACTLY one sentence, max 100 characters
        - Describe WHAT the branch does, not HOW
        - Be specific and informative
        - Output ONLY the sentence, nothing else
        """,
            untrustedSections: [
                AIUntrustedPromptSection(
                    kind: "branch_name",
                    label: "Branch",
                    content: branchName,
                    maxLength: 120
                ),
                AIUntrustedPromptSection(
                    kind: "commit_log",
                    label: "Commits since diverging",
                    content: commitLog,
                    maxLength: AILimits.maxCommitLogLength
                ),
                AIUntrustedPromptSection(
                    kind: "diff_stat",
                    label: "Diff stat",
                    content: diffStat,
                    maxLength: AILimits.maxDiffStatLength
                ),
            ]
        )
        return try await call(payload: payload, provider: provider, apiKey: apiKey, maxTokens: AILimits.branchSummaryTokens, lane: .cheapSummary, mode: mode)
    }

    // MARK: - Bisect Culprit Explanation

    func explainBisectCulprit(
        commitHash: String,
        diff: String,
        diffStat: String,
        provider: AIProvider,
        apiKey: String,
        mode: AIMode
    ) async throws -> String {
        let payload = Self.makePromptPayload(
            task: "Explain a git bisect culprit",
            taskInstructions: """
            Git bisect found the first bad commit that introduced a regression.

            Explain:
        1. What this commit changed
        2. Why it likely caused the regression
        3. What to look for to fix it

        Rules:
        - Plain English, max 150 words
        - No code blocks
        - Be specific about which changes are suspicious
        - Output ONLY the explanation
        """,
            untrustedSections: [
                AIUntrustedPromptSection(
                    kind: "commit_hash",
                    label: "Commit hash",
                    content: String(commitHash.prefix(12)),
                    maxLength: 12
                ),
                AIUntrustedPromptSection(
                    kind: "diff_stat",
                    label: "Files changed",
                    content: diffStat,
                    maxLength: AILimits.maxDiffStatLength
                ),
                AIUntrustedPromptSection(
                    kind: "diff",
                    label: "Diff",
                    content: diff,
                    maxLength: AILimits.maxDiffContentLength
                ),
            ]
        )
        return try await call(payload: payload, provider: provider, apiKey: apiKey, maxTokens: AILimits.bisectExplainTokens, lane: .reasoning, mode: mode)
    }

    // MARK: - Smart Conflict Resolution

    func resolveConflict(
        oursLines: [String],
        theirsLines: [String],
        oursLabel: String,
        theirsLabel: String,
        surroundingContext: String,
        fileName: String,
        provider: AIProvider,
        apiKey: String,
        mode: AIMode,
        repoContext: String = ""
    ) async throws -> String {
        let ours = oursLines.joined(separator: "\n")
        let theirs = theirsLines.joined(separator: "\n")
        let payload = Self.makePromptPayload(
            task: "Resolve a merge conflict",
            taskInstructions: """
            Analyze both sides of a merge conflict and produce a semantically correct resolution.

            Rules:
        - Output ONLY the resolved code, nothing else. No explanation, no markers.
        - Combine both changes when they don't conflict semantically.
        - If they truly conflict, prefer the most complete/correct version.
        - Preserve indentation and coding style from the surrounding context.
        - Do NOT include conflict markers in the output.
        """,
            untrustedSections: [
                AIUntrustedPromptSection(
                    kind: "file_name",
                    label: "File name",
                    content: fileName,
                    maxLength: 240
                ),
                AIUntrustedPromptSection(
                    kind: "ours_conflict_chunk",
                    label: "Conflict chunk (ours)",
                    content: "<<<<<<< \(oursLabel) (OURS)\n\(ours)",
                    maxLength: AILimits.maxDiffContentLength / 2
                ),
                AIUntrustedPromptSection(
                    kind: "theirs_conflict_chunk",
                    label: "Conflict chunk (theirs)",
                    content: "=======\n\(theirs)\n>>>>>>> \(theirsLabel) (THEIRS)",
                    maxLength: AILimits.maxDiffContentLength / 2
                ),
                AIUntrustedPromptSection(
                    kind: "surrounding_context",
                    label: "Surrounding context",
                    content: surroundingContext,
                    maxLength: AILimits.maxSurroundingContextLength
                ),
                AIUntrustedPromptSection(
                    kind: "repository_conventions",
                    label: "Repository conventions",
                    content: repoContextBlock(repoContext),
                    maxLength: AILimits.maxRepoContextLength
                ),
            ]
        )
        return try await call(payload: payload, provider: provider, apiKey: apiKey, maxTokens: AILimits.conflictResolutionTokens, lane: .reasoning, mode: mode)
    }

    // MARK: - Commit Split Advisor

    func suggestCommitSplit(
        diff: String,
        diffStat: String,
        provider: AIProvider,
        apiKey: String,
        mode: AIMode,
        repoContext: String = ""
    ) async throws -> [CommitSuggestion] {
        let payload = Self.makePromptPayload(
            task: "Suggest how to split staged changes into atomic commits",
            taskInstructions: """
            The user has staged a large change. Suggest how to split it into atomic commits.

            Output format — one commit per block, separated by blank lines:
        MESSAGE: commit message here
        FILES: file1.swift, file2.swift

        Rules:
        - Suggest 2-5 atomic commits
        - Each commit should be a logical unit
        - Messages follow Conventional Commits format
        - List exact file paths from the diff stat
        - Output ONLY the formatted blocks, nothing else
        """,
            untrustedSections: [
                AIUntrustedPromptSection(
                    kind: "repository_conventions",
                    label: "Repository conventions",
                    content: repoContextBlock(repoContext),
                    maxLength: AILimits.maxRepoContextLength
                ),
                AIUntrustedPromptSection(
                    kind: "diff_stat",
                    label: "Diff stat",
                    content: diffStat,
                    maxLength: AILimits.maxDiffStatLength
                ),
                AIUntrustedPromptSection(
                    kind: "diff",
                    label: "Diff",
                    content: diff,
                    maxLength: AILimits.maxDiffContentLength
                ),
            ]
        )
        let raw = try await call(payload: payload, provider: provider, apiKey: apiKey, maxTokens: AILimits.commitSplitTokens, lane: .reasoning, mode: mode)
        return parseCommitSuggestions(raw)
    }

    // MARK: - Pending Changes Summary

    func summarizePendingChanges(
        diffStat: String,
        fileList: String,
        provider: AIProvider,
        apiKey: String,
        mode: AIMode
    ) async throws -> String {
        let payload = Self.makePromptPayload(
            task: "Summarize pending changes",
            taskInstructions: """
            Summarize what the developer has been working on based on pending changes.

            Rules:
        - 1-2 sentences, plain English, conversational tone
        - Focus on the INTENT (what they're trying to accomplish), not individual files
        - Example: "You've been refactoring the auth module and fixing sidebar CSS."
        - Output ONLY the summary, nothing else
        """,
            untrustedSections: [
                AIUntrustedPromptSection(
                    kind: "changed_files",
                    label: "Changed files",
                    content: fileList,
                    maxLength: AILimits.maxPendingChangesFileListLength
                ),
                AIUntrustedPromptSection(
                    kind: "diff_stat",
                    label: "Diff stat",
                    content: diffStat,
                    maxLength: AILimits.maxPendingChangesDiffStatLength
                ),
            ]
        )
        return try await call(payload: payload, provider: provider, apiKey: apiKey, maxTokens: AILimits.pendingSummaryTokens, lane: .cheapSummary, mode: mode)
    }
}
