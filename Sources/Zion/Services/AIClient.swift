import Foundation
import Security

actor AIClient {

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
        SecItemAdd(add as CFDictionary, nil)
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

    // MARK: - API Calls

    func generateCommitMessage(
        diff: String,
        diffStat: String,
        recentMessages: [String],
        branchName: String,
        provider: AIProvider,
        apiKey: String
    ) async throws -> String {
        let recentStyle = recentMessages.prefix(10).joined(separator: "\n")
        let prompt = """
        You are an expert Git commit message generator. Analyze the provided changes and write a single-line commit message.

        Match the style of these recent commits from the repository:
        \(recentStyle)

        Branch: \(branchName)

        Diff stat:
        \(diffStat.prefix(2000))

        Diff / Content summary (truncated):
        \(diff.prefix(10000))

        Rules:
        - Output EXACTLY one line. NO "Commit:" or "Message:" prefix.
        - Use the format: type(scope): description (Conventional Commits).
        - Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert.
        - Scope: The most relevant component or folder affected (e.g. "auth", "ui", "core").
        - Description: Concise summary of WHAT and WHY, in the imperative mood (e.g., "add user login" NOT "Added user login").
        - MAX 72 characters.
        - NEVER output generic messages like "update files" if you can infer intent from the diff content.
        """
        return try await call(prompt: prompt, provider: provider, apiKey: apiKey, maxTokens: 100)
    }

    func generatePRDescription(
        commitLog: String,
        diffStat: String,
        branchName: String,
        baseBranch: String,
        provider: AIProvider,
        apiKey: String
    ) async throws -> (title: String, body: String) {
        let prompt = """
        You are a Pull Request description generator. Generate a PR title and body for merging \(branchName) into \(baseBranch).

        Commits:
        \(commitLog.prefix(3000))

        Diff stat:
        \(diffStat.prefix(2000))

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
        """
        let raw = try await call(prompt: prompt, provider: provider, apiKey: apiKey, maxTokens: 600)
        return parsePRResponse(raw)
    }

    func generateStashMessage(
        diff: String,
        diffStat: String,
        provider: AIProvider,
        apiKey: String
    ) async throws -> String {
        let prompt = """
        You are a Git stash message generator. Write a short, descriptive stash name for the following work-in-progress changes.

        Diff stat:
        \(diffStat.prefix(2000))

        Diff (truncated):
        \(diff.prefix(3000))

        Rules:
        - Output ONLY the stash message, nothing else
        - Be descriptive but concise (max 60 characters)
        - Describe WHAT the changes are about
        - Example style: "WIP: refactor auth flow" or "Add user avatar upload"
        """
        return try await call(prompt: prompt, provider: provider, apiKey: apiKey, maxTokens: 60)
    }

    func explainDiff(
        fileDiff: String,
        fileName: String,
        provider: AIProvider,
        apiKey: String
    ) async throws -> String {
        let prompt = """
        You are a code reviewer. Explain the following diff for the file "\(fileName)" in 2-3 plain-English sentences. Focus on WHAT changed and WHY it matters.

        Diff:
        \(fileDiff.prefix(10000))

        Rules:
        - 2-3 sentences maximum
        - Plain English, no code blocks
        - Focus on the intent behind the changes
        - Output ONLY the explanation
        """
        return try await call(prompt: prompt, provider: provider, apiKey: apiKey, maxTokens: 200)
    }

    // MARK: - Private

    private func call(prompt: String, provider: AIProvider, apiKey: String, maxTokens: Int) async throws -> String {
        switch provider {
        case .anthropic:
            return try await callAnthropic(prompt: prompt, apiKey: apiKey, maxTokens: maxTokens)
        case .openai:
            return try await callOpenAI(prompt: prompt, apiKey: apiKey, maxTokens: maxTokens)
        case .gemini:
            return try await callGemini(prompt: prompt, apiKey: apiKey, maxTokens: maxTokens)
        case .none:
            throw AIError.noProvider
        }
    }

    private func callGemini(prompt: String, apiKey: String, maxTokens: Int) async throws -> String {
        // Using gemini-2.5-flash-lite: the fastest and most cost-effective model
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "maxOutputTokens": maxTokens
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }

        if http.statusCode == 400 || http.statusCode == 401 { throw AIError.invalidKey }
        if http.statusCode == 429 { throw AIError.quotaExceeded }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.apiError("Gemini \(http.statusCode): \(msg)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let candidates = json?["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw AIError.invalidResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func callAnthropic(prompt: String, apiKey: String, maxTokens: Int) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": "claude-3-5-haiku-20241022",
            "max_tokens": maxTokens,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }

        if http.statusCode == 401 { throw AIError.invalidKey }
        if http.statusCode == 429 { throw AIError.quotaExceeded }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.apiError("Anthropic \(http.statusCode): \(msg)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw AIError.invalidResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func callOpenAI(prompt: String, apiKey: String, maxTokens: Int) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": maxTokens
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }

        if http.statusCode == 401 { throw AIError.invalidKey }
        if http.statusCode == 429 { throw AIError.quotaExceeded }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.apiError("OpenAI \(http.statusCode): \(msg)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw AIError.invalidResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parsePRResponse(_ raw: String) -> (title: String, body: String) {
        let lines = raw.components(separatedBy: "\n")
        var title = ""
        var bodyLines: [String] = []
        var inBody = false

        for line in lines {
            if line.hasPrefix("TITLE:") {
                title = line.replacingOccurrences(of: "TITLE:", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("BODY:") {
                inBody = true
            } else if inBody {
                bodyLines.append(line)
            }
        }

        if title.isEmpty {
            // Fallback: use first line as title, rest as body
            title = lines.first ?? ""
            bodyLines = Array(lines.dropFirst())
        }

        return (title, bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

// MARK: - Error Types

enum AIError: LocalizedError {
    case noProvider
    case invalidKey
    case invalidResponse
    case quotaExceeded
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noProvider: return L10n("Nenhum provedor de IA configurado")
        case .invalidKey: return L10n("Chave de API invalida")
        case .invalidResponse: return L10n("Resposta invalida da API")
        case .quotaExceeded: return L10n("Cota da API excedida ou saldo insuficiente")
        case .apiError(let msg): return msg
        }
    }
}
