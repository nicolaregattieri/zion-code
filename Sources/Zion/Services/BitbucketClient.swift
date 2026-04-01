import Foundation

actor BitbucketClient: GitHostingProvider {
    let kind: GitHostingKind = .bitbucket
    private var cachedCredentials: (username: String, appPassword: String)?
    private var didAttemptKeychainLookup = false

    /// Invalidate cached credentials so the next API call re-resolves.
    func invalidateCache() {
        cachedCredentials = nil
        didAttemptKeychainLookup = false
    }

    // MARK: - Auth

    nonisolated func checkAuthStatus() -> (installed: Bool, authenticated: Bool) {
        (true, true)
    }

    func hasToken() async -> Bool {
        !HostingAccountStore.accounts(for: .bitbucket).isEmpty || resolveLegacyCredentials() != nil
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

    /// Resolve auth header for a specific remote using multi-account matching.
    private func resolveAuthHeader(for remote: HostedRemote) -> String? {
        guard let creds = resolveCredentialsForRemote(remote) else { return nil }
        let credString = "\(creds.username):\(creds.appPassword)"
        guard let data = credString.data(using: .utf8) else { return nil }
        return "Basic \(data.base64EncodedString())"
    }

    /// Multi-account credential resolution.
    private func resolveCredentialsForRemote(_ remote: HostedRemote) -> (username: String, appPassword: String)? {
        if let account = HostingAccountStore.resolveAccount(for: remote),
           let secret = HostingAccountStore.loadSecret(for: account)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !secret.isEmpty,
           let bbUser = account.bitbucketUsername, !bbUser.isEmpty {
            return (username: bbUser, appPassword: secret)
        }
        return resolveLegacyCredentials()
    }

    /// Legacy single-account credential resolution.
    private func resolveLegacyCredentials() -> (username: String, appPassword: String)? {
        if let creds = cachedCredentials,
           !creds.username.isEmpty,
           !creds.appPassword.isEmpty {
            return creds
        }
        if didAttemptKeychainLookup {
            return nil
        }
        didAttemptKeychainLookup = true

        let username = UserDefaults.standard.string(forKey: UserDefaultsKeys.GitHosting.bitbucketUsername)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let appPassword = HostingCredentialStore.loadSecret(for: .bitbucketAppPassword)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !username.isEmpty, !appPassword.isEmpty else { return nil }

        let resolved = (username: username, appPassword: appPassword)
        cachedCredentials = resolved
        return resolved
    }

    /// Percent-encode a path segment.
    private static func encodePathSegment(_ segment: String) -> String? {
        segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    }

    // MARK: - Owner Discovery

    /// Fetch the authenticated username and accessible workspaces for a given credential.
    static func fetchAccessibleOwners(username: String, appPassword: String) async -> (username: String, owners: [String]) {
        let credString = "\(username):\(appPassword)"
        guard let credData = credString.data(using: .utf8) else { return (username, [username]) }
        let auth = "Basic \(credData.base64EncodedString())"

        guard let url = URL(string: "https://api.bitbucket.org/2.0/user/permissions/workspaces?pagelen=100") else {
            return (username, [username])
        }
        var request = URLRequest(url: url)
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        var workspaces: [String] = []
        if let (data, response) = try? await URLSession.shared.data(for: request),
           let http = response as? HTTPURLResponse, http.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let values = json["values"] as? [[String: Any]] {
            workspaces = values.compactMap { ($0["workspace"] as? [String: Any])?["slug"] as? String }
        }

        return (username: username, owners: [username] + workspaces)
    }

    // MARK: - GitHostingProvider

    func fetchPullRequests(remote: HostedRemote) async -> [HostedPRInfo] {
        guard let auth = resolveAuthHeader(for: remote) else { return [] }
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
        guard let auth = resolveAuthHeader(for: remote) else { return nil }
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
        guard let auth = resolveAuthHeader(for: remote) else { return [] }
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
        guard let auth = resolveAuthHeader(for: remote) else { throw HostingError.noToken }
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
