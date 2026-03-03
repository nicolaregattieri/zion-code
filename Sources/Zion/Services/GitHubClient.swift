import Foundation

actor GitHubClient: GitHostingProvider {
    let kind: GitHostingKind = .github
    private var injectedPAT: String?
    private var cachedCLIToken: String?
    private var cachedUsername: String?

    /// Inject a PAT for authentication. Called from settings when the user configures GitHub credentials.
    func setToken(_ token: String?) {
        let cleaned = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        injectedPAT = (cleaned?.isEmpty == true) ? nil : cleaned
        // Clear cached CLI token so getToken() re-evaluates priority
        cachedCLIToken = nil
        cachedUsername = nil
    }

    // MARK: - Auth

    /// Check if `gh` CLI is installed and authenticated
    nonisolated func checkAuthStatus() -> (installed: Bool, authenticated: Bool) {
        Self.checkGHStatus()
    }

    /// Static variant for backward compatibility in views.
    nonisolated static func checkGHStatus() -> (installed: Bool, authenticated: Bool) {
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["gh"]
        whichProcess.standardOutput = Pipe()
        whichProcess.standardError = Pipe()
        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()
            guard whichProcess.terminationStatus == 0 else { return (false, false) }
        } catch { return (false, false) }

        let authProcess = Process()
        authProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        authProcess.arguments = ["gh", "auth", "status"]
        authProcess.standardOutput = Pipe()
        authProcess.standardError = Pipe()
        do {
            try authProcess.run()
            authProcess.waitUntilExit()
            return (true, authProcess.terminationStatus == 0)
        } catch { return (true, false) }
    }

    // MARK: - Remote Parsing

    /// Parse GitHub owner/repo from a remote URL
    static func parseRemote(_ urlString: String) -> HostedRemote? {
        // SSH: git@github.com:owner/repo.git (also handles SSH aliases like github.com-personal)
        if let sshMatch = urlString.range(of: "github\\.com[^:/]*[:/]([^/]+)/([^/]+?)(\\.git)?$", options: .regularExpression) {
            let segment = String(urlString[sshMatch])
            // Strip the host prefix (github.com or github.com-alias) and .git suffix
            let cleaned = segment
                .replacingOccurrences(of: ".git", with: "")
                .replacingOccurrences(of: "github\\.com[^:/]*[:/]", with: "", options: .regularExpression)
            let parts = cleaned.split(separator: "/")
            if parts.count >= 2 {
                return HostedRemote(kind: .github, owner: String(parts[0]), repo: String(parts[1]))
            }
        }
        // HTTPS: https://github.com/owner/repo.git
        if let url = URL(string: urlString),
           url.host?.contains("github.com") == true {
            let components = url.pathComponents.filter { $0 != "/" }
            if components.count >= 2 {
                let repo = components[1].replacingOccurrences(of: ".git", with: "")
                return HostedRemote(kind: .github, owner: components[0], repo: repo)
            }
        }
        return nil
    }

    // MARK: - Token

    private func getToken() async -> String? {
        // 1. Settings PAT takes priority
        if let pat = injectedPAT { return pat }

        // 2. Fall back to `gh auth token` CLI
        if let cached = cachedCLIToken { return cached }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh", "auth", "token"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let token, !token.isEmpty {
                    cachedCLIToken = token
                    return token
                }
            }
        } catch {}

        // 3. No token available
        return nil
    }

    /// Check whether any authentication is configured (PAT or `gh` CLI).
    func hasToken() async -> Bool {
        await getToken() != nil
    }

    /// Percent-encode a path segment for safe GitHub API URL interpolation.
    private static func encodePathSegment(_ segment: String) -> String? {
        segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    }

    // MARK: - Authenticated Username

    private func fetchAuthenticatedUsername(token: String) async -> String? {
        if let cached = cachedUsername { return cached }

        let urlString = "https://api.github.com/user"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let login = json["login"] as? String else { return nil }
            cachedUsername = login
            return login
        } catch {
            return nil
        }
    }

    // MARK: - GitHostingProvider

    func fetchPullRequests(remote: HostedRemote) async -> [HostedPRInfo] {
        let token = await getToken()
        guard let owner = Self.encodePathSegment(remote.owner),
              let repo = Self.encodePathSegment(remote.repo) else { return [] }
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/pulls?state=open&per_page=30"
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

            return json.compactMap { pr -> HostedPRInfo? in
                guard let id = pr["id"] as? Int,
                      let number = pr["number"] as? Int,
                      let title = pr["title"] as? String,
                      let stateStr = pr["state"] as? String,
                      let head = pr["head"] as? [String: Any],
                      let base = pr["base"] as? [String: Any],
                      let htmlUrl = pr["html_url"] as? String,
                      let headRef = head["ref"] as? String,
                      let baseRef = base["ref"] as? String else { return nil }

                let isDraft = pr["draft"] as? Bool ?? false
                let user = pr["user"] as? [String: Any]
                let author = user?["login"] as? String ?? ""
                let headSHA = (head["sha"] as? String) ?? ""
                let state: HostedPRInfo.PRState = stateStr == "open" ? .open : .closed

                return HostedPRInfo(
                    id: id, number: number, title: title, state: state,
                    headBranch: headRef, baseBranch: baseRef,
                    url: htmlUrl, isDraft: isDraft, author: author,
                    headSHA: headSHA
                )
            }
        } catch {
            return []
        }
    }

    func fetchPRsRequestingMyReview(remote: HostedRemote) async -> [HostedPRInfo] {
        guard let token = await getToken() else { return [] }
        guard let username = await fetchAuthenticatedUsername(token: token) else { return [] }

        guard let owner = Self.encodePathSegment(remote.owner),
              let repo = Self.encodePathSegment(remote.repo) else { return [] }
        let query = "type:pr+state:open+review-requested:\(username)+repo:\(owner)/\(repo)"
        let urlString = "https://api.github.com/search/issues?q=\(query)&per_page=30"
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else { return [] }

            return items.compactMap { item -> HostedPRInfo? in
                guard let id = item["id"] as? Int,
                      let number = item["number"] as? Int,
                      let title = item["title"] as? String,
                      let htmlUrl = item["html_url"] as? String else { return nil }

                let user = item["user"] as? [String: Any]
                let author = user?["login"] as? String ?? ""

                return HostedPRInfo(
                    id: id, number: number, title: title, state: .open,
                    headBranch: "", baseBranch: "",
                    url: htmlUrl, isDraft: false, author: author,
                    headSHA: ""
                )
            }
        } catch {
            return []
        }
    }

    func fetchPRDiff(remote: HostedRemote, prNumber: Int) async -> String? {
        guard let token = await getToken() else { return nil }
        guard let owner = Self.encodePathSegment(remote.owner),
              let repo = Self.encodePathSegment(remote.repo) else { return nil }
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/pulls/\(prNumber)"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.diff", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    func fetchPRFiles(remote: HostedRemote, prNumber: Int) async -> [(filename: String, status: String, additions: Int, deletions: Int, patch: String)] {
        guard let token = await getToken() else { return [] }
        guard let owner = Self.encodePathSegment(remote.owner),
              let repo = Self.encodePathSegment(remote.repo) else { return [] }
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/pulls/\(prNumber)/files?per_page=100"
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

            return json.compactMap { file in
                guard let filename = file["filename"] as? String,
                      let status = file["status"] as? String else { return nil }
                let additions = file["additions"] as? Int ?? 0
                let deletions = file["deletions"] as? Int ?? 0
                let patch = file["patch"] as? String ?? ""
                return (filename: filename, status: status, additions: additions, deletions: deletions, patch: patch)
            }
        } catch {
            return []
        }
    }

    func createPullRequest(remote: HostedRemote, title: String, body: String, head: String, base: String, draft: Bool) async throws -> HostedPRInfo {
        guard let token = await getToken() else {
            throw HostingError.noToken
        }

        guard let owner = Self.encodePathSegment(remote.owner),
              let repo = Self.encodePathSegment(remote.repo) else {
            throw HostingError.invalidURL
        }
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/pulls"
        guard let url = URL(string: urlString) else {
            throw HostingError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "title": title,
            "body": body,
            "head": head,
            "base": base,
            "draft": draft
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw HostingError.apiError(msg)
        }

        guard let pr = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = pr["id"] as? Int,
              let number = pr["number"] as? Int,
              let htmlUrl = pr["html_url"] as? String else {
            throw HostingError.parseError
        }

        let headObj = pr["head"] as? [String: Any]
        let headSHA = (headObj?["sha"] as? String) ?? ""

        return HostedPRInfo(
            id: id, number: number, title: title, state: .open,
            headBranch: head, baseBranch: base,
            url: htmlUrl, isDraft: draft, author: "",
            headSHA: headSHA
        )
    }

    // MARK: - PR Comments & Reviews (Phase 2)

    func fetchPRComments(remote: HostedRemote, prNumber: Int) async -> [PRComment] {
        guard let token = await getToken() else { return [] }
        guard let owner = Self.encodePathSegment(remote.owner),
              let repo = Self.encodePathSegment(remote.repo) else { return [] }
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/pulls/\(prNumber)/comments?per_page=100"
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fallbackFormatter = ISO8601DateFormatter()

            return json.compactMap { comment -> PRComment? in
                guard let id = comment["id"] as? Int,
                      let body = comment["body"] as? String,
                      let path = comment["path"] as? String else { return nil }

                let user = comment["user"] as? [String: Any]
                let author = user?["login"] as? String ?? ""
                let line = comment["line"] as? Int ?? comment["original_line"] as? Int
                let createdStr = comment["created_at"] as? String ?? ""
                let updatedStr = comment["updated_at"] as? String ?? ""
                let createdAt = formatter.date(from: createdStr) ?? fallbackFormatter.date(from: createdStr) ?? Date()
                let updatedAt = formatter.date(from: updatedStr) ?? fallbackFormatter.date(from: updatedStr) ?? Date()
                let inReplyToID = comment["in_reply_to_id"] as? Int

                return PRComment(
                    id: id, author: author, body: body, path: path,
                    line: line, createdAt: createdAt, updatedAt: updatedAt,
                    inReplyToID: inReplyToID
                )
            }
        } catch {
            return []
        }
    }

    func postPRComment(remote: HostedRemote, prNumber: Int, body: String, commitID: String, path: String, line: Int) async throws -> PRComment {
        guard let token = await getToken() else { throw HostingError.noToken }
        guard let owner = Self.encodePathSegment(remote.owner),
              let repo = Self.encodePathSegment(remote.repo) else { throw HostingError.invalidURL }
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/pulls/\(prNumber)/comments"
        guard let url = URL(string: urlString) else { throw HostingError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "body": body,
            "commit_id": commitID,
            "path": path,
            "line": line,
            "side": "RIGHT"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw HostingError.apiError(msg)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? Int else {
            throw HostingError.parseError
        }

        let user = json["user"] as? [String: Any]
        let author = user?["login"] as? String ?? ""

        return PRComment(
            id: id, author: author, body: body, path: path,
            line: line, createdAt: Date(), updatedAt: Date(),
            inReplyToID: nil
        )
    }

    func fetchPRReviews(remote: HostedRemote, prNumber: Int) async -> [PRReviewSummary] {
        guard let token = await getToken() else { return [] }
        guard let owner = Self.encodePathSegment(remote.owner),
              let repo = Self.encodePathSegment(remote.repo) else { return [] }
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/pulls/\(prNumber)/reviews"
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fallbackFormatter = ISO8601DateFormatter()

            return json.compactMap { review -> PRReviewSummary? in
                guard let id = review["id"] as? Int,
                      let stateStr = review["state"] as? String else { return nil }

                let user = review["user"] as? [String: Any]
                let author = user?["login"] as? String ?? ""
                let body = review["body"] as? String ?? ""
                let submittedStr = review["submitted_at"] as? String
                let submittedAt = submittedStr.flatMap { formatter.date(from: $0) ?? fallbackFormatter.date(from: $0) }

                let state: PRReviewEvent
                switch stateStr.uppercased() {
                case "APPROVED": state = .approve
                case "CHANGES_REQUESTED": state = .requestChanges
                default: state = .comment
                }

                return PRReviewSummary(id: id, author: author, state: state, body: body, submittedAt: submittedAt)
            }
        } catch {
            return []
        }
    }

    func submitPRReview(remote: HostedRemote, prNumber: Int, body: String, event: PRReviewEvent, comments: [PRReviewDraftComment]) async throws {
        guard let token = await getToken() else { throw HostingError.noToken }
        guard let owner = Self.encodePathSegment(remote.owner),
              let repo = Self.encodePathSegment(remote.repo) else { throw HostingError.invalidURL }
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/pulls/\(prNumber)/reviews"
        guard let url = URL(string: urlString) else { throw HostingError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = [
            "body": body,
            "event": event.rawValue
        ]

        if !comments.isEmpty {
            payload["comments"] = comments.map { comment -> [String: Any] in
                [
                    "path": comment.path,
                    "line": comment.line,
                    "body": comment.body,
                    "side": "RIGHT"
                ]
            }
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw HostingError.apiError(msg)
        }
    }
}

/// Legacy error type — maps to HostingError for backward compatibility.
typealias GitHubError = HostingError
