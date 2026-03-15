import Foundation

// MARK: - Code Review & Explanation

extension AIClient {

    // MARK: - Code Review

    func reviewDiff(
        diff: String,
        diffStat: String,
        branchName: String,
        provider: AIProvider,
        apiKey: String,
        mode: AIMode,
        repoContext: String = ""
    ) async throws -> [ReviewFinding] {
        let payload = Self.makePromptPayload(
            task: "Review a staged diff",
            taskInstructions: """
            Analyze the staged diff and find bugs, security issues, and style problems.

            Output format — one finding per line, pipe-delimited:
        SEVERITY|FILE|MESSAGE|EVIDENCE|TEST_IMPACT

        Where SEVERITY is one of: critical, warning, suggestion
        FILE is the affected filename (or "general" if not file-specific)
        MESSAGE is a concise description of the issue
        EVIDENCE is a short quote or hunk summary grounding the finding, or "-"
        TEST_IMPACT is a likely test area or missing coverage hint, or "-"

        Rules:
        - Output ONLY the pipe-delimited lines, nothing else
        - Focus on real issues: bugs, security vulnerabilities, race conditions, missing error handling
        - Include style suggestions only if they're significant
        - Maximum 10 findings
        - If the code looks good, output a single line: suggestion|general|Code looks good — no issues found.|-|-
        """,
            untrustedSections: [
                AIUntrustedPromptSection(
                    kind: "branch_name",
                    label: "Branch",
                    content: branchName,
                    maxLength: 120
                ),
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
        let raw = try await call(payload: payload, provider: provider, apiKey: apiKey, maxTokens: AILimits.codeReviewTokens, lane: .review, mode: mode)
        return Self.parseReviewFindings(raw)
    }

    func reviewBranch(
        diff: String,
        diffStat: String,
        sourceBranch: String,
        targetBranch: String,
        provider: AIProvider,
        apiKey: String,
        mode: AIMode,
        repoContext: String = ""
    ) async throws -> [ReviewFinding] {
        let payload = Self.makePromptPayload(
            task: "Review a branch diff",
            taskInstructions: """
            Analyze the diff between two branches and find bugs, security issues, and architectural problems.

            Output format — one finding per line, pipe-delimited:
        SEVERITY|FILE|MESSAGE|EVIDENCE|TEST_IMPACT

        Where SEVERITY is one of: critical, warning, suggestion
        FILE is the affected filename (or "general" if not file-specific)
        MESSAGE is a concise description of the issue
        EVIDENCE is a short quote or hunk summary grounding the finding, or "-"
        TEST_IMPACT is a likely test area or missing coverage hint, or "-"

        Rules:
        - Output ONLY the pipe-delimited lines, nothing else
        - Focus on real issues: logic bugs, security vulnerabilities, breaking changes
        - Maximum 15 findings
        - If the code looks good, output a single line: suggestion|general|No issues found between branches.|-|-
        """,
            untrustedSections: [
                AIUntrustedPromptSection(
                    kind: "source_branch",
                    label: "Source branch",
                    content: sourceBranch,
                    maxLength: 120
                ),
                AIUntrustedPromptSection(
                    kind: "target_branch",
                    label: "Target branch",
                    content: targetBranch,
                    maxLength: 120
                ),
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
        let raw = try await call(payload: payload, provider: provider, apiKey: apiKey, maxTokens: AILimits.branchReviewTokens, lane: .review, mode: mode)
        return Self.parseReviewFindings(raw)
    }

    // MARK: - Per-file Code Review

    func reviewFile(
        fileDiff: String,
        fileName: String,
        provider: AIProvider,
        apiKey: String,
        mode: AIMode,
        repoContext: String = ""
    ) async throws -> [ReviewFinding] {
        let payload = Self.makePromptPayload(
            task: "Review a single file diff",
            taskInstructions: """
            Analyze the diff for a single file and find bugs, security issues, and problems.

            Output format — one finding per line, pipe-delimited:
        SEVERITY|FILE|MESSAGE|EVIDENCE|TEST_IMPACT

        Where SEVERITY is one of: critical, warning, suggestion
        FILE is "\(fileName)"
        MESSAGE is a concise description of the issue
        EVIDENCE is a short quote or hunk summary grounding the finding, or "-"
        TEST_IMPACT is a likely test area or missing coverage hint, or "-"

        Rules:
        - Output ONLY the pipe-delimited lines, nothing else
        - Focus on real issues in THIS specific file
        - Maximum 5 findings per file
        - If the code looks good, output: suggestion|<file>|No issues found.|-|-
        """,
            untrustedSections: [
                AIUntrustedPromptSection(
                    kind: "file_name",
                    label: "File name",
                    content: fileName,
                    maxLength: 240
                ),
                AIUntrustedPromptSection(
                    kind: "repository_conventions",
                    label: "Repository conventions",
                    content: repoContextBlock(repoContext),
                    maxLength: AILimits.maxRepoContextLength
                ),
                AIUntrustedPromptSection(
                    kind: "diff",
                    label: "Diff",
                    content: fileDiff,
                    maxLength: AILimits.maxDiffContentLength
                ),
            ]
        )
        let raw = try await call(payload: payload, provider: provider, apiKey: apiKey, maxTokens: AILimits.fileReviewTokens, lane: .review, mode: mode)
        return Self.parseReviewFindings(raw)
    }

    // MARK: - Blame Explainer

    func explainBlameRegion(
        commitHash: String,
        fileName: String,
        commitDiff: String,
        commitSubject: String,
        regionContent: String,
        provider: AIProvider,
        apiKey: String,
        mode: AIMode,
        repoContext: String = ""
    ) async throws -> String {
        let payload = Self.makePromptPayload(
            task: "Explain why a blamed code region changed",
            taskInstructions: """
            Explain WHY this code change was made based on the commit context.

            Rules:
        - 2-3 sentences explaining the intent behind the change
        - Focus on WHY, not WHAT (the user can see the code)
        - Plain English, no code blocks
        - Output ONLY the explanation
        """,
            untrustedSections: [
                AIUntrustedPromptSection(
                    kind: "commit_hash",
                    label: "Commit hash",
                    content: commitHash,
                    maxLength: 120
                ),
                AIUntrustedPromptSection(
                    kind: "commit_subject",
                    label: "Commit subject",
                    content: commitSubject,
                    maxLength: 240
                ),
                AIUntrustedPromptSection(
                    kind: "file_name",
                    label: "File name",
                    content: fileName,
                    maxLength: 240
                ),
                AIUntrustedPromptSection(
                    kind: "blame_region_content",
                    label: "Blame region content",
                    content: regionContent,
                    maxLength: AILimits.maxBlameRegionLength
                ),
                AIUntrustedPromptSection(
                    kind: "commit_diff",
                    label: "Commit diff for this file",
                    content: commitDiff,
                    maxLength: AILimits.maxBlameDiffLength
                ),
                AIUntrustedPromptSection(
                    kind: "repository_conventions",
                    label: "Repository conventions",
                    content: repoContextBlock(repoContext),
                    maxLength: AILimits.maxRepoContextLength
                ),
            ]
        )
        return try await call(payload: payload, provider: provider, apiKey: apiKey, maxTokens: AILimits.blameExplanationTokens, lane: .reasoning, mode: mode)
    }

    // MARK: - Detailed Diff Explanation

    func explainDiffDetailed(
        fileDiff: String,
        fileName: String,
        provider: AIProvider,
        apiKey: String,
        mode: AIMode,
        repoContext: String = ""
    ) async throws -> DiffExplanation {
        let payload = Self.makePromptPayload(
            task: "Provide a structured diff explanation",
            taskInstructions: """
            Analyze the diff and provide a structured explanation.

            Output format (exactly — each section on its own line):
        INTENT: <1-2 sentences explaining the purpose/motivation of this change>
        RISKS: <1-2 sentences about potential risks, breaking changes, or things to watch out for>
        NARRATIVE: <1-2 sentences telling the story of this change — what was the developer thinking>
        SEVERITY: <one of: safe, moderate, risky>

        Rules:
        - Output ONLY the four lines above, nothing else
        - SEVERITY must be exactly one of: safe, moderate, risky
        - "safe" = no risks, routine change
        - "moderate" = some edge cases or minor concerns
        - "risky" = breaking changes, security implications, or complex logic
        - Be specific and technical, not generic
        """,
            untrustedSections: [
                AIUntrustedPromptSection(
                    kind: "file_name",
                    label: "File name",
                    content: fileName,
                    maxLength: 240
                ),
                AIUntrustedPromptSection(
                    kind: "repository_conventions",
                    label: "Repository conventions",
                    content: repoContextBlock(repoContext),
                    maxLength: AILimits.maxRepoContextLength
                ),
                AIUntrustedPromptSection(
                    kind: "diff",
                    label: "Diff",
                    content: fileDiff,
                    maxLength: AILimits.maxDiffContentLength
                ),
            ]
        )
        let raw = try await call(payload: payload, provider: provider, apiKey: apiKey, maxTokens: AILimits.detailedDiffTokens, lane: .review, mode: mode)
        return parseDiffExplanation(raw)
    }
}
