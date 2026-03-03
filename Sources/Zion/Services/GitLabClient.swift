import Foundation

actor GitLabClient: GitHostingProvider {
    let kind: GitHostingKind = .gitlab
    private var cachedToken: String?

    /// Inject a PAT for authentication. Called from settings when the user configures GitLab credentials.
    func setToken(_ token: String?) {
        cachedToken = token
    }

    // MARK: - Auth

    nonisolated func checkAuthStatus() -> (installed: Bool, authenticated: Bool) {
        // GitLab uses PAT stored in keychain via GitCredentialStore — always "installed"
        (true, true)
    }

    func hasToken() async -> Bool {
        cachedToken != nil && !(cachedToken?.isEmpty ?? true)
    }

    // MARK: - Remote Parsing

    static func parseRemote(_ urlString: String) -> HostedRemote? {
        // SSH: git@gitlab.com:owner/repo.git  or  git@self-hosted.com:group/subgroup/repo.git
        if let sshMatch = urlString.range(of: "git@([^:]+):(.+?)(\\.git)?$", options: .regularExpression) {
            let segment = String(urlString[sshMatch])
            // Extract host
            guard let atRange = segment.range(of: "@"),
                  let colonRange = segment.range(of: ":", range: atRange.upperBound..<segment.endIndex) else { return nil }
            let host = String(segment[atRange.upperBound..<colonRange.lowerBound])
            guard !host.contains("github.com"), !host.contains("bitbucket") else { return nil }

            var pathPart = String(segment[colonRange.upperBound...])
            if pathPart.hasSuffix(".git") { pathPart = String(pathPart.dropLast(4)) }
            let parts = pathPart.split(separator: "/")
            guard parts.count >= 2 else { return nil }

            let repo = String(parts.last!)
            let owner = parts.dropLast().map(String.init).joined(separator: "/")
            let isCloud = host == "gitlab.com"
            return HostedRemote(kind: .gitlab, owner: owner, repo: repo, host: isCloud ? nil : host)
        }

        // HTTPS: https://gitlab.com/owner/repo.git
        if let url = URL(string: urlString),
           let host = url.host,
           host.contains("gitlab") || (!host.contains("github") && !host.contains("bitbucket")) {
            // Only match if it looks like gitlab
            guard host.contains("gitlab") else { return nil }
            let components = url.pathComponents.filter { $0 != "/" }
            guard components.count >= 2 else { return nil }

            let repo = components.last!.replacingOccurrences(of: ".git", with: "")
            let owner = components.dropLast().joined(separator: "/")
            let isCloud = host == "gitlab.com"
            return HostedRemote(kind: .gitlab, owner: owner, repo: repo, host: isCloud ? nil : host)
        }

        return nil
    }

    // MARK: - Token

    private func getToken() -> String? {
        cachedToken
    }

    /// URL-encode a project path for GitLab API (owner/repo → owner%2Frepo).
    private static func encodeProjectPath(_ owner: String, _ repo: String) -> String? {
        "\(owner)/\(repo)".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)?
            .replacingOccurrences(of: "/", with: "%2F")
    }

    // MARK: - GitHostingProvider

    func fetchPullRequests(remote: HostedRemote) async -> [HostedPRInfo] {
        guard let token = getToken() else { return [] }
        guard let projectPath = Self.encodeProjectPath(remote.owner, remote.repo) else { return [] }
        let baseURL = remote.apiBaseURL
        let urlString = "\(baseURL)/projects/\(projectPath)/merge_requests?state=opened&per_page=30"
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

            return json.compactMap { mr -> HostedPRInfo? in
                guard let id = mr["id"] as? Int,
                      let iid = mr["iid"] as? Int,
                      let title = mr["title"] as? String,
                      let webUrl = mr["web_url"] as? String else { return nil }

                let sourceBranch = mr["source_branch"] as? String ?? ""
                let targetBranch = mr["target_branch"] as? String ?? ""
                let isDraft = mr["draft"] as? Bool ?? (mr["work_in_progress"] as? Bool ?? false)
                let author = (mr["author"] as? [String: Any])?["username"] as? String ?? ""
                let sha = mr["sha"] as? String ?? ""

                return HostedPRInfo(
                    id: id, number: iid, title: title, state: .open,
                    headBranch: sourceBranch, baseBranch: targetBranch,
                    url: webUrl, isDraft: isDraft, author: author,
                    headSHA: sha
                )
            }
        } catch {
            return []
        }
    }

    func fetchPRsRequestingMyReview(remote: HostedRemote) async -> [HostedPRInfo] {
        guard let token = getToken() else { return [] }
        guard let projectPath = Self.encodeProjectPath(remote.owner, remote.repo) else { return [] }
        let baseURL = remote.apiBaseURL
        let urlString = "\(baseURL)/projects/\(projectPath)/merge_requests?state=opened&reviewer_username=self&per_page=30"
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

            return json.compactMap { mr -> HostedPRInfo? in
                guard let id = mr["id"] as? Int,
                      let iid = mr["iid"] as? Int,
                      let title = mr["title"] as? String,
                      let webUrl = mr["web_url"] as? String else { return nil }

                let sourceBranch = mr["source_branch"] as? String ?? ""
                let targetBranch = mr["target_branch"] as? String ?? ""
                let author = (mr["author"] as? [String: Any])?["username"] as? String ?? ""

                return HostedPRInfo(
                    id: id, number: iid, title: title, state: .open,
                    headBranch: sourceBranch, baseBranch: targetBranch,
                    url: webUrl, isDraft: false, author: author,
                    headSHA: ""
                )
            }
        } catch {
            return []
        }
    }

    func fetchPRDiff(remote: HostedRemote, prNumber: Int) async -> String? {
        guard let token = getToken() else { return nil }
        guard let projectPath = Self.encodeProjectPath(remote.owner, remote.repo) else { return nil }
        let baseURL = remote.apiBaseURL
        let urlString = "\(baseURL)/projects/\(projectPath)/merge_requests/\(prNumber)/changes"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let changes = json["changes"] as? [[String: Any]] else { return nil }

            return changes.compactMap { change -> String? in
                change["diff"] as? String
            }.joined(separator: "\n")
        } catch {
            return nil
        }
    }

    func fetchPRFiles(remote: HostedRemote, prNumber: Int) async -> [(filename: String, status: String, additions: Int, deletions: Int, patch: String)] {
        guard let token = getToken() else { return [] }
        guard let projectPath = Self.encodeProjectPath(remote.owner, remote.repo) else { return [] }
        let baseURL = remote.apiBaseURL
        let urlString = "\(baseURL)/projects/\(projectPath)/merge_requests/\(prNumber)/changes"
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let changes = json["changes"] as? [[String: Any]] else { return [] }

            return changes.compactMap { change in
                let newPath = change["new_path"] as? String ?? ""
                let diff = change["diff"] as? String ?? ""
                let isNew = change["new_file"] as? Bool ?? false
                let isDeleted = change["deleted_file"] as? Bool ?? false
                let isRenamed = change["renamed_file"] as? Bool ?? false
                let status: String
                if isNew { status = "added" }
                else if isDeleted { status = "removed" }
                else if isRenamed { status = "renamed" }
                else { status = "modified" }

                // Count additions/deletions from diff
                let lines = diff.components(separatedBy: "\n")
                let additions = lines.filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count
                let deletions = lines.filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.count

                return (filename: newPath, status: status, additions: additions, deletions: deletions, patch: diff)
            }
        } catch {
            return []
        }
    }

    func createPullRequest(remote: HostedRemote, title: String, body: String, head: String, base: String, draft: Bool) async throws -> HostedPRInfo {
        guard let token = getToken() else { throw HostingError.noToken }
        guard let projectPath = Self.encodeProjectPath(remote.owner, remote.repo) else { throw HostingError.invalidURL }
        let baseURL = remote.apiBaseURL
        let urlString = "\(baseURL)/projects/\(projectPath)/merge_requests"
        guard let url = URL(string: urlString) else { throw HostingError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = [
            "title": draft ? "Draft: \(title)" : title,
            "description": body,
            "source_branch": head,
            "target_branch": base
        ]
        if draft { payload["draft"] = true }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw HostingError.apiError(msg)
        }

        guard let mr = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = mr["id"] as? Int,
              let iid = mr["iid"] as? Int,
              let webUrl = mr["web_url"] as? String else {
            throw HostingError.parseError
        }

        return HostedPRInfo(
            id: id, number: iid, title: title, state: .open,
            headBranch: head, baseBranch: base,
            url: webUrl, isDraft: draft, author: "",
            headSHA: ""
        )
    }
}
