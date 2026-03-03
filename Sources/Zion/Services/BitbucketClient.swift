import Foundation

actor BitbucketClient: GitHostingProvider {
    let kind: GitHostingKind = .bitbucket
    private var cachedCredentials: (username: String, appPassword: String)?

    /// Inject credentials for authentication. Called from settings.
    func setCredentials(username: String, appPassword: String) {
        if username.isEmpty || appPassword.isEmpty {
            cachedCredentials = nil
        } else {
            cachedCredentials = (username, appPassword)
        }
    }

    // MARK: - Auth

    nonisolated func checkAuthStatus() -> (installed: Bool, authenticated: Bool) {
        (true, true)
    }

    func hasToken() async -> Bool {
        cachedCredentials != nil
    }

    // MARK: - Remote Parsing

    static func parseRemote(_ urlString: String) -> HostedRemote? {
        // SSH: git@bitbucket.org:owner/repo.git
        if let sshMatch = urlString.range(of: "bitbucket\\.org[:/]([^/]+)/([^/]+?)(\\.git)?$", options: .regularExpression) {
            let segment = String(urlString[sshMatch])
            let parts = segment
                .replacingOccurrences(of: "bitbucket.org:", with: "")
                .replacingOccurrences(of: "bitbucket.org/", with: "")
                .replacingOccurrences(of: ".git", with: "")
                .split(separator: "/")
            if parts.count >= 2 {
                return HostedRemote(kind: .bitbucket, owner: String(parts[0]), repo: String(parts[1]))
            }
        }
        // HTTPS: https://bitbucket.org/owner/repo.git
        if let url = URL(string: urlString),
           url.host?.contains("bitbucket") == true {
            let components = url.pathComponents.filter { $0 != "/" }
            if components.count >= 2 {
                let repo = components[1].replacingOccurrences(of: ".git", with: "")
                return HostedRemote(kind: .bitbucket, owner: components[0], repo: repo)
            }
        }
        return nil
    }

    // MARK: - Auth Header

    private func authHeader() -> String? {
        guard let creds = cachedCredentials else { return nil }
        let credString = "\(creds.username):\(creds.appPassword)"
        guard let data = credString.data(using: .utf8) else { return nil }
        return "Basic \(data.base64EncodedString())"
    }

    /// Percent-encode a path segment.
    private static func encodePathSegment(_ segment: String) -> String? {
        segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    }

    // MARK: - GitHostingProvider

    func fetchPullRequests(remote: HostedRemote) async -> [HostedPRInfo] {
        guard let auth = authHeader() else { return [] }
        guard let owner = Self.encodePathSegment(remote.owner),
              let repo = Self.encodePathSegment(remote.repo) else { return [] }
        let urlString = "https://api.bitbucket.org/2.0/repositories/\(owner)/\(repo)/pullrequests?state=OPEN&pagelen=30"
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(auth, forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let values = json["values"] as? [[String: Any]] else { return [] }

            return values.compactMap { pr -> HostedPRInfo? in
                guard let id = pr["id"] as? Int,
                      let title = pr["title"] as? String else { return nil }

                let source = pr["source"] as? [String: Any]
                let dest = pr["destination"] as? [String: Any]
                let sourceBranch = (source?["branch"] as? [String: Any])?["name"] as? String ?? ""
                let destBranch = (dest?["branch"] as? [String: Any])?["name"] as? String ?? ""
                let sourceCommit = (source?["commit"] as? [String: Any])?["hash"] as? String ?? ""

                let links = pr["links"] as? [String: Any]
                let htmlLink = (links?["html"] as? [String: Any])?["href"] as? String ?? ""

                let author = (pr["author"] as? [String: Any])?["nickname"] as? String
                    ?? (pr["author"] as? [String: Any])?["display_name"] as? String ?? ""

                return HostedPRInfo(
                    id: id, number: id, title: title, state: .open,
                    headBranch: sourceBranch, baseBranch: destBranch,
                    url: htmlLink, isDraft: false, author: author,
                    headSHA: sourceCommit
                )
            }
        } catch {
            return []
        }
    }

    func fetchPRsRequestingMyReview(remote: HostedRemote) async -> [HostedPRInfo] {
        // Bitbucket REST API v2 doesn't have a direct "requesting my review" filter
        // Return empty — users can see all open PRs in the "All Open" tab
        []
    }

    func fetchPRDiff(remote: HostedRemote, prNumber: Int) async -> String? {
        guard let auth = authHeader() else { return nil }
        guard let owner = Self.encodePathSegment(remote.owner),
              let repo = Self.encodePathSegment(remote.repo) else { return nil }
        let urlString = "https://api.bitbucket.org/2.0/repositories/\(owner)/\(repo)/pullrequests/\(prNumber)/diff"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(auth, forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    func fetchPRFiles(remote: HostedRemote, prNumber: Int) async -> [(filename: String, status: String, additions: Int, deletions: Int, patch: String)] {
        guard let auth = authHeader() else { return [] }
        guard let owner = Self.encodePathSegment(remote.owner),
              let repo = Self.encodePathSegment(remote.repo) else { return [] }
        let urlString = "https://api.bitbucket.org/2.0/repositories/\(owner)/\(repo)/pullrequests/\(prNumber)/diffstat?pagelen=100"
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(auth, forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let values = json["values"] as? [[String: Any]] else { return [] }

            return values.compactMap { stat in
                let newPath = (stat["new"] as? [String: Any])?["path"] as? String
                let oldPath = (stat["old"] as? [String: Any])?["path"] as? String
                let filename = newPath ?? oldPath ?? ""
                guard !filename.isEmpty else { return nil }

                let statusStr = stat["status"] as? String ?? "modified"
                let linesAdded = stat["lines_added"] as? Int ?? 0
                let linesRemoved = stat["lines_removed"] as? Int ?? 0

                return (filename: filename, status: statusStr, additions: linesAdded, deletions: linesRemoved, patch: "")
            }
        } catch {
            return []
        }
    }

    func createPullRequest(remote: HostedRemote, title: String, body: String, head: String, base: String, draft: Bool) async throws -> HostedPRInfo {
        guard let auth = authHeader() else { throw HostingError.noToken }
        guard let owner = Self.encodePathSegment(remote.owner),
              let repo = Self.encodePathSegment(remote.repo) else { throw HostingError.invalidURL }
        let urlString = "https://api.bitbucket.org/2.0/repositories/\(owner)/\(repo)/pullrequests"
        guard let url = URL(string: urlString) else { throw HostingError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "title": title,
            "description": body,
            "source": ["branch": ["name": head]],
            "destination": ["branch": ["name": base]],
            "close_source_branch": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw HostingError.apiError(msg)
        }

        guard let pr = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = pr["id"] as? Int else {
            throw HostingError.parseError
        }

        let links = pr["links"] as? [String: Any]
        let htmlLink = (links?["html"] as? [String: Any])?["href"] as? String ?? ""

        return HostedPRInfo(
            id: id, number: id, title: title, state: .open,
            headBranch: head, baseBranch: base,
            url: htmlLink, isDraft: false, author: "",
            headSHA: ""
        )
    }
}
