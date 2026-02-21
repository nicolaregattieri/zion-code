import Foundation

struct GitHubPRInfo: Identifiable, Sendable {
    let id: Int
    let number: Int
    let title: String
    let state: PRState
    let headBranch: String
    let baseBranch: String
    let url: String
    let isDraft: Bool
    let author: String

    enum PRState: String, Sendable {
        case open, closed, merged

        var label: String {
            switch self {
            case .open: return "Open"
            case .closed: return "Closed"
            case .merged: return "Merged"
            }
        }
    }
}

struct GitHubRemote: Sendable {
    let owner: String
    let repo: String
}

actor GitHubClient {
    private var cachedToken: String?

    /// Parse GitHub owner/repo from a remote URL
    static func parseRemote(_ urlString: String) -> GitHubRemote? {
        // SSH: git@github.com:owner/repo.git
        if let sshMatch = urlString.range(of: "github\\.com[:/]([^/]+)/([^/]+?)(\\.git)?$", options: .regularExpression) {
            let segment = String(urlString[sshMatch])
            let parts = segment
                .replacingOccurrences(of: "github.com:", with: "")
                .replacingOccurrences(of: "github.com/", with: "")
                .replacingOccurrences(of: ".git", with: "")
                .split(separator: "/")
            if parts.count >= 2 {
                return GitHubRemote(owner: String(parts[0]), repo: String(parts[1]))
            }
        }
        // HTTPS: https://github.com/owner/repo.git
        if let url = URL(string: urlString),
           url.host?.contains("github.com") == true {
            let components = url.pathComponents.filter { $0 != "/" }
            if components.count >= 2 {
                let repo = components[1].replacingOccurrences(of: ".git", with: "")
                return GitHubRemote(owner: components[0], repo: repo)
            }
        }
        return nil
    }

    /// Try to get auth token from gh CLI
    private func getToken() async -> String? {
        if let cached = cachedToken { return cached }

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
                    cachedToken = token
                    return token
                }
            }
        } catch {}
        return nil
    }

    /// Fetch open PRs for a repo
    func fetchPullRequests(remote: GitHubRemote) async -> [GitHubPRInfo] {
        let token = await getToken()
        let urlString = "https://api.github.com/repos/\(remote.owner)/\(remote.repo)/pulls?state=open&per_page=30"
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

            return json.compactMap { pr -> GitHubPRInfo? in
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
                let state: GitHubPRInfo.PRState = stateStr == "open" ? .open : .closed

                return GitHubPRInfo(
                    id: id, number: number, title: title, state: state,
                    headBranch: headRef, baseBranch: baseRef,
                    url: htmlUrl, isDraft: isDraft, author: author
                )
            }
        } catch {
            return []
        }
    }

    /// Fetch PRs requesting review from the authenticated user using the search API
    func fetchPRsRequestingMyReview(remote: GitHubRemote) async -> [GitHubPRInfo] {
        guard let token = await getToken() else { return [] }
        guard let username = await fetchAuthenticatedUsername(token: token) else { return [] }

        let query = "type:pr+state:open+review-requested:\(username)+repo:\(remote.owner)/\(remote.repo)"
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

            return items.compactMap { item -> GitHubPRInfo? in
                guard let id = item["id"] as? Int,
                      let number = item["number"] as? Int,
                      let title = item["title"] as? String,
                      let htmlUrl = item["html_url"] as? String else { return nil }

                let user = item["user"] as? [String: Any]
                let author = user?["login"] as? String ?? ""

                return GitHubPRInfo(
                    id: id, number: number, title: title, state: .open,
                    headBranch: "", baseBranch: "",
                    url: htmlUrl, isDraft: false, author: author
                )
            }
        } catch {
            return []
        }
    }

    private var cachedUsername: String?

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

    /// Fetch the diff for a specific PR
    func fetchPRDiff(remote: GitHubRemote, prNumber: Int) async -> String? {
        guard let token = await getToken() else { return nil }
        let urlString = "https://api.github.com/repos/\(remote.owner)/\(remote.repo)/pulls/\(prNumber)"
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

    /// Fetch files changed in a PR
    func fetchPRFiles(remote: GitHubRemote, prNumber: Int) async -> [(filename: String, status: String, additions: Int, deletions: Int, patch: String)] {
        guard let token = await getToken() else { return [] }
        let urlString = "https://api.github.com/repos/\(remote.owner)/\(remote.repo)/pulls/\(prNumber)/files?per_page=100"
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

    /// Create a pull request
    func createPullRequest(remote: GitHubRemote, title: String, body: String, head: String, base: String, draft: Bool) async throws -> GitHubPRInfo {
        guard let token = await getToken() else {
            throw GitHubError.noToken
        }

        let urlString = "https://api.github.com/repos/\(remote.owner)/\(remote.repo)/pulls"
        guard let url = URL(string: urlString) else {
            throw GitHubError.invalidURL
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
            throw GitHubError.apiError(msg)
        }

        guard let pr = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = pr["id"] as? Int,
              let number = pr["number"] as? Int,
              let htmlUrl = pr["html_url"] as? String else {
            throw GitHubError.parseError
        }

        return GitHubPRInfo(
            id: id, number: number, title: title, state: .open,
            headBranch: head, baseBranch: base,
            url: htmlUrl, isDraft: draft, author: ""
        )
    }
}

enum GitHubError: LocalizedError {
    case noToken
    case invalidURL
    case apiError(String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .noToken: return "GitHub token nao encontrado. Execute 'gh auth login' no terminal."
        case .invalidURL: return "URL invalida."
        case .apiError(let msg): return "GitHub API: \(msg)"
        case .parseError: return "Erro ao processar resposta do GitHub."
        }
    }
}
