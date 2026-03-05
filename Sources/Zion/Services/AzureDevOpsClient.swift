import Foundation

actor AzureDevOpsClient: GitHostingProvider {
    let kind: GitHostingKind = .azureDevOps
    private var cachedToken: String?
    private var didAttemptKeychainLookup = false

    private static let apiVersion = "7.1"

    /// Inject PAT for authentication. Called from settings.
    func setToken(_ token: String?) {
        if let token, !token.isEmpty {
            cachedToken = token
        } else {
            cachedToken = nil
        }
        didAttemptKeychainLookup = false
    }

    // MARK: - Auth

    nonisolated func checkAuthStatus() -> (installed: Bool, authenticated: Bool) {
        (true, true)
    }

    func hasToken() async -> Bool {
        resolvedToken() != nil
    }

    // MARK: - Remote Parsing

    /// Parses Azure DevOps remote URLs in 4 formats:
    /// - `https://dev.azure.com/org/project/_git/repo`
    /// - `https://org.visualstudio.com/project/_git/repo`
    /// - `git@ssh.dev.azure.com:v3/org/project/repo`
    /// - `git@vs-ssh.visualstudio.com:v3/org/project/repo`
    static func parseRemote(_ urlString: String) -> HostedRemote? {
        // SSH: git@ssh.dev.azure.com:v3/org/project/repo
        if let range = urlString.range(of: "ssh\\.dev\\.azure\\.com:v3/([^/]+)/([^/]+)/([^/]+?)(\\.git)?$", options: .regularExpression) {
            let segment = String(urlString[range])
            let cleaned = segment.replacingOccurrences(of: "ssh.dev.azure.com:v3/", with: "").replacingOccurrences(of: ".git", with: "")
            let parts = cleaned.split(separator: "/")
            if parts.count >= 3 {
                return HostedRemote(kind: .azureDevOps, owner: String(parts[0]), repo: String(parts[2]), host: "dev.azure.com", project: String(parts[1]))
            }
        }

        // SSH: git@vs-ssh.visualstudio.com:v3/org/project/repo
        if let range = urlString.range(of: "vs-ssh\\.visualstudio\\.com:v3/([^/]+)/([^/]+)/([^/]+?)(\\.git)?$", options: .regularExpression) {
            let segment = String(urlString[range])
            let cleaned = segment.replacingOccurrences(of: "vs-ssh.visualstudio.com:v3/", with: "").replacingOccurrences(of: ".git", with: "")
            let parts = cleaned.split(separator: "/")
            if parts.count >= 3 {
                return HostedRemote(kind: .azureDevOps, owner: String(parts[0]), repo: String(parts[2]), host: "dev.azure.com", project: String(parts[1]))
            }
        }

        // HTTPS: https://dev.azure.com/org/project/_git/repo
        if let url = URL(string: urlString), url.host == "dev.azure.com" {
            let components = url.pathComponents.filter { $0 != "/" }
            // Expected: [org, project, _git, repo]
            if components.count >= 4, components[2] == "_git" {
                let repo = components[3].replacingOccurrences(of: ".git", with: "")
                return HostedRemote(kind: .azureDevOps, owner: components[0], repo: repo, host: "dev.azure.com", project: components[1])
            }
        }

        // HTTPS: https://org.visualstudio.com/project/_git/repo
        if let url = URL(string: urlString), let host = url.host, host.hasSuffix(".visualstudio.com") {
            let org = host.replacingOccurrences(of: ".visualstudio.com", with: "")
            let components = url.pathComponents.filter { $0 != "/" }
            // Expected: [project, _git, repo]
            if components.count >= 3, components[1] == "_git" {
                let repo = components[2].replacingOccurrences(of: ".git", with: "")
                return HostedRemote(kind: .azureDevOps, owner: org, repo: repo, host: "dev.azure.com", project: components[0])
            }
        }

        return nil
    }

    // MARK: - Auth Header

    /// ADO uses Basic auth with empty username and PAT as password.
    private func authHeader() -> String? {
        guard let token = resolvedToken() else { return nil }
        let credString = ":\(token)"
        guard let data = credString.data(using: .utf8) else { return nil }
        return "Basic \(data.base64EncodedString())"
    }

    private func resolvedToken() -> String? {
        if let token = cachedToken, !token.isEmpty {
            return token
        }
        if !didAttemptKeychainLookup {
            didAttemptKeychainLookup = true
            if let keychainToken = HostingCredentialStore.loadSecret(for: .azureDevOpsPAT)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !keychainToken.isEmpty {
                cachedToken = keychainToken
                return keychainToken
            }
        }
        return nil
    }

    /// Build an ADO REST API URL for a repository endpoint.
    private func adoURL(path: String, remote: HostedRemote) -> URL? {
        guard let project = remote.project else { return nil }
        let base = remote.apiBaseURL
        let urlString = "\(base)/\(project)/_apis/git/repositories/\(remote.repo)/\(path)?api-version=\(Self.apiVersion)"
        return URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString)
    }

    // MARK: - GitHostingProvider

    func fetchPullRequests(remote: HostedRemote) async -> [HostedPRInfo] {
        guard let auth = authHeader() else { return [] }
        guard let url = adoURL(path: "pullrequests", remote: remote) else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(auth, forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let values = json["value"] as? [[String: Any]] else { return [] }
            return values.compactMap { parsePR($0, remote: remote) }
        } catch {
            return []
        }
    }

    func fetchPRsRequestingMyReview(remote: HostedRemote) async -> [HostedPRInfo] {
        // ADO doesn't have a simple "requesting my review" filter; return empty for now
        []
    }

    func fetchPRDiff(remote: HostedRemote, prNumber: Int) async -> String? {
        // ADO has no simple diff endpoint; deferred (requires iteration-based reconstruction)
        nil
    }

    func fetchPRFiles(remote: HostedRemote, prNumber: Int) async -> [(filename: String, status: String, additions: Int, deletions: Int, patch: String)] {
        []
    }

    func createPullRequest(remote: HostedRemote, title: String, body: String, head: String, base: String, draft: Bool) async throws -> HostedPRInfo {
        guard let auth = authHeader() else { throw HostingError.noToken }
        guard let url = adoURL(path: "pullrequests", remote: remote) else { throw HostingError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "sourceRefName": "refs/heads/\(head)",
            "targetRefName": "refs/heads/\(base)",
            "title": title,
            "description": body,
            "isDraft": draft,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HostingError.parseError }

        if http.statusCode == 201 || http.statusCode == 200 {
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pr = parsePR(json, remote: remote) else {
                throw HostingError.parseError
            }
            return pr
        } else {
            let msg = parseErrorMessage(data) ?? "HTTP \(http.statusCode)"
            throw HostingError.apiError(msg)
        }
    }

    // MARK: - Parsing

    private func parsePR(_ json: [String: Any], remote: HostedRemote) -> HostedPRInfo? {
        guard let id = json["pullRequestId"] as? Int,
              let title = json["title"] as? String,
              let statusStr = json["status"] as? String else { return nil }

        let state: HostedPRInfo.PRState
        switch statusStr {
        case "active": state = .open
        case "completed": state = .merged
        case "abandoned": state = .closed
        default: state = .open
        }

        let sourceRef = (json["sourceRefName"] as? String) ?? ""
        let targetRef = (json["targetRefName"] as? String) ?? ""
        let headBranch = sourceRef.replacingOccurrences(of: "refs/heads/", with: "")
        let baseBranch = targetRef.replacingOccurrences(of: "refs/heads/", with: "")

        let isDraft = json["isDraft"] as? Bool ?? false

        var author = ""
        if let createdBy = json["createdBy"] as? [String: Any] {
            author = (createdBy["displayName"] as? String) ?? (createdBy["uniqueName"] as? String) ?? ""
        }

        let lastMergeSourceCommit = json["lastMergeSourceCommit"] as? [String: Any]
        let headSHA = (lastMergeSourceCommit?["commitId"] as? String) ?? ""

        let host = remote.host ?? "dev.azure.com"
        let prURL = "https://\(host)/\(remote.owner)/\(remote.project ?? "")/_git/\(remote.repo)/pullrequest/\(id)"

        return HostedPRInfo(
            id: id,
            number: id,
            title: title,
            state: state,
            headBranch: headBranch,
            baseBranch: baseBranch,
            url: prURL,
            isDraft: isDraft,
            author: author,
            headSHA: headSHA
        )
    }

    private func parseErrorMessage(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["message"] as? String
    }
}
