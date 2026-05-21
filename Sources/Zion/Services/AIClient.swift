import Foundation
import Security

enum AILimits {
    static let maxDiffStatLength = 2000
    static let maxDiffContentLength = 10_000
    static let maxCommitLogLength = 3000
    static let maxChangelogLogLength = 5000
    static let maxSemanticSearchLogLength = 6000
    static let maxBlameRegionLength = 1000
    static let maxBlameDiffLength = 5000
    static let maxPendingChangesFileListLength = 3000
    static let maxPendingChangesDiffStatLength = 5000
    static let maxSurroundingContextLength = 3000
    static let maxRepoContextLength = 1600

    // Token limits per operation
    static let compactMessageTokens = 100
    static let detailedMessageTokens = 400
    static let prDescriptionTokens = 600
    static let stashMessageTokens = 60
    static let diffExplanationTokens = 200
    static let conflictResolutionTokens = 500
    static let codeReviewTokens = 800
    static let branchReviewTokens = 1000
    static let changelogTokens = 1000
    static let semanticSearchTokens = 260
    static let branchSummaryTokens = 60
    static let blameExplanationTokens = 200
    static let commitSplitTokens = 600
    static let detailedDiffTokens = 400
    static let fileReviewTokens = 400
    static let pendingSummaryTokens = 150
    static let bisectExplainTokens = 600
    static let maxFileContentPreviewLength = 8_000
}

struct AIUntrustedPromptSection {
    let kind: String
    let label: String
    let content: String
    let maxLength: Int
}

struct AIPromptPayload {
    let systemInstructions: String
    let taskInstructions: String
    let untrustedSections: [AIUntrustedPromptSection]
    let suspiciousPatterns: [String]
}

actor AIClient {

    // MARK: - Injectable URLSession (test-only)

    /// Injected URLSession used by the `.local` dispatch path. Nil in production (uses URLSession.shared).
    var _testURLSession: URLSession? = nil

    /// Sets the injectable URLSession. For use in unit tests only.
    func set_testURLSession(_ session: URLSession) {
        _testURLSession = session
    }

    // MARK: - Keychain

    private static let keychainService = "com.zion.ai-api-key"

    static func saveAPIKey(_ key: String, for provider: AIProvider) {
        guard provider != .none else { return }
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: provider.rawValue,
        ]

        // Delete any existing item first
        SecItemDelete(query as CFDictionary)

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        _ = SecItemAdd(add as CFDictionary, nil)
    }

    static func loadAPIKey(for provider: AIProvider) -> String? {
        guard provider != .none else { return nil }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteAPIKey(for provider: AIProvider) {
        guard provider != .none else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: provider.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // Deprecated helpers for backward compatibility (migrate to "default" if exists)
    private static func migrateLegacyKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "default",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, let _ = String(data: data, encoding: .utf8) {
            // Migrating to Anthropic as a guess or simply keeping it for a while
            // For now, let's just leave it but the new methods won't use it.
        }
    }

    // MARK: - Core Generation

    func generateCommitMessage(
        diff: String,
        diffStat: String,
        recentMessages: [String],
        branchName: String,
        provider: AIProvider,
        apiKey: String,
        style: CommitMessageStyle = .compact,
        mode: AIMode,
        repoContext: String = ""
    ) async throws -> String {
        let recentStyle = recentMessages.prefix(10).joined(separator: "\n")
        let taskInstructions: String
        let maxTokens: Int

        switch style {
        case .compact:
            taskInstructions = """
            Analyze the repository changes and write a single-line commit message.

            Rules:
            - Output EXACTLY one line. NO "Commit:" or "Message:" prefix.
            - Use the format: type(scope): description (Conventional Commits).
            - Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert.
            - Scope: The most relevant component or folder affected (e.g. "auth", "ui", "core").
            - Description: Concise summary of WHAT and WHY, in the imperative mood (e.g., "add user login" NOT "Added user login").
            - MAX 72 characters.
            - NEVER output generic messages like "update files" if you can infer intent from the diff content.
            """
            maxTokens = AILimits.compactMessageTokens

        case .detailed:
            taskInstructions = """
            Analyze the repository changes and write a detailed commit message.

            Rules:
            - First line: type(scope): short summary (Conventional Commits, max 72 chars).
            - Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert.
            - Scope: The most relevant component or folder affected (e.g. "auth", "ui", "core").
            - Leave a blank line after the first line.
            - Then list 3-7 bullet points starting with "- ", each describing a specific change.
            - Each bullet: imperative mood, concise, specific (e.g., "- Add validation for email input").
            - NO "Commit:" or "Message:" prefix. Output ONLY the commit message.
            - NEVER output generic messages like "update files" if you can infer intent from the diff content.
            """
            maxTokens = AILimits.detailedMessageTokens
        }

        let payload = Self.makePromptPayload(
            task: "Generate a git commit message",
            taskInstructions: taskInstructions,
            untrustedSections: [
                AIUntrustedPromptSection(
                    kind: "recent_commit_subjects",
                    label: "Recent commit subjects",
                    content: recentStyle,
                    maxLength: AILimits.maxCommitLogLength
                ),
                AIUntrustedPromptSection(
                    kind: "repository_conventions",
                    label: "Repository conventions",
                    content: repoContextBlock(repoContext),
                    maxLength: AILimits.maxRepoContextLength
                ),
                AIUntrustedPromptSection(
                    kind: "branch_name",
                    label: "Branch name",
                    content: branchName,
                    maxLength: 120
                ),
                AIUntrustedPromptSection(
                    kind: "diff_stat",
                    label: "Diff stat",
                    content: diffStat,
                    maxLength: AILimits.maxDiffStatLength
                ),
                AIUntrustedPromptSection(
                    kind: "diff",
                    label: "Diff and content summary",
                    content: diff,
                    maxLength: AILimits.maxDiffContentLength
                ),
            ]
        )

        return try await call(payload: payload, provider: provider, apiKey: apiKey, maxTokens: maxTokens, lane: .general, mode: mode)
    }

    func generatePRDescription(
        commitLog: String,
        diffStat: String,
        branchName: String,
        baseBranch: String,
        provider: AIProvider,
        apiKey: String,
        mode: AIMode,
        repoContext: String = ""
    ) async throws -> (title: String, body: String) {
        let payload = Self.makePromptPayload(
            task: "Generate a pull request title and body",
            taskInstructions: """
            Generate a PR title and body for a merge.

            Output format (exactly):
        TITLE: <short PR title, max 70 chars>
        BODY:
        ## Summary
        - <bullet point 1>
        - <bullet point 2>
        - <bullet point 3>

        ## Changes
        <brief description of what changed>

        Rules:
        - Title should be concise and descriptive
        - Body uses markdown
        - Focus on the "why" and user impact
        - Keep it professional and clear
        """,
            untrustedSections: [
                AIUntrustedPromptSection(
                    kind: "source_branch",
                    label: "Source branch",
                    content: branchName,
                    maxLength: 120
                ),
                AIUntrustedPromptSection(
                    kind: "target_branch",
                    label: "Target branch",
                    content: baseBranch,
                    maxLength: 120
                ),
                AIUntrustedPromptSection(
                    kind: "repository_conventions",
                    label: "Repository conventions",
                    content: repoContextBlock(repoContext),
                    maxLength: AILimits.maxRepoContextLength
                ),
                AIUntrustedPromptSection(
                    kind: "commit_log",
                    label: "Commits",
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
        let raw = try await call(payload: payload, provider: provider, apiKey: apiKey, maxTokens: AILimits.prDescriptionTokens, lane: .reasoning, mode: mode)
        return parsePRResponse(raw)
    }

    func generateStashMessage(
        diff: String,
        diffStat: String,
        provider: AIProvider,
        apiKey: String,
        mode: AIMode
    ) async throws -> String {
        let payload = Self.makePromptPayload(
            task: "Generate a git stash message",
            taskInstructions: """
            Write a short, descriptive stash name for the provided work-in-progress changes.

            Rules:
        - Output ONLY the stash message, nothing else
        - Be descriptive but concise (max 60 characters)
        - Describe WHAT the changes are about
        - Example style: "WIP: refactor auth flow" or "Add user avatar upload"
        """,
            untrustedSections: [
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
                    maxLength: AILimits.maxCommitLogLength
                ),
            ]
        )
        return try await call(payload: payload, provider: provider, apiKey: apiKey, maxTokens: AILimits.stashMessageTokens, lane: .cheapSummary, mode: mode)
    }

    func explainDiff(
        fileDiff: String,
        fileName: String,
        provider: AIProvider,
        apiKey: String,
        mode: AIMode
    ) async throws -> String {
        let payload = Self.makePromptPayload(
            task: "Explain a file diff",
            taskInstructions: """
            Explain the file diff in 2-3 plain-English sentences. Focus on WHAT changed and WHY it matters.

            Rules:
        - 2-3 sentences maximum
        - Plain English, no code blocks
        - Focus on the intent behind the changes
        - Output ONLY the explanation
        """,
            untrustedSections: [
                AIUntrustedPromptSection(
                    kind: "file_name",
                    label: "File name",
                    content: fileName,
                    maxLength: 240
                ),
                AIUntrustedPromptSection(
                    kind: "diff",
                    label: "Diff",
                    content: fileDiff,
                    maxLength: AILimits.maxDiffContentLength
                ),
            ]
        )
        return try await call(payload: payload, provider: provider, apiKey: apiKey, maxTokens: AILimits.diffExplanationTokens, lane: .general, mode: mode)
    }
}
