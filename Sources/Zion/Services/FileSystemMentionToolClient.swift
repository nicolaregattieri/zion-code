import Foundation

/// Local-filesystem MentionToolClient used by ChatService for live @file/@folder/@web
/// expansion without round-tripping through the MCP server.
/// - read_file: reads `args["path"]` relative to (or under) repoURL; rejects path traversal.
/// - list_dir: returns newline-separated entries of `args["path"]` under repoURL.
/// - web_fetch: GET on `args["url"]`, 10s timeout, capped at 256 KB.
final class FileSystemMentionToolClient: MentionToolClient, @unchecked Sendable {

    private let repoURL: URL
    private let session: URLSession
    private static let webTimeout: TimeInterval = 10
    private static let webByteCap: Int = 256 * 1024

    init(repoURL: URL, session: URLSession = .shared) {
        self.repoURL = repoURL.standardizedFileURL.resolvingSymlinksInPath()
        self.session = session
    }

    func callTool(_ name: String, args: [String: Any]) async throws -> String {
        switch name {
        case "read_file":
            return try readFile(args)
        case "list_dir":
            return try listDir(args)
        case "web_fetch":
            return try await webFetch(args)
        default:
            throw FSMentionError.unknownTool(name)
        }
    }

    private func readFile(_ args: [String: Any]) throws -> String {
        guard let path = args["path"] as? String, !path.isEmpty else {
            throw FSMentionError.missingArgument("path")
        }
        let url = try resolve(path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func listDir(_ args: [String: Any]) throws -> String {
        guard let path = args["path"] as? String, !path.isEmpty else {
            throw FSMentionError.missingArgument("path")
        }
        let url = try resolve(path)
        let entries = try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
        return entries.joined(separator: "\n")
    }

    private func webFetch(_ args: [String: Any]) async throws -> String {
        guard let urlString = args["url"] as? String, let url = URL(string: urlString) else {
            throw FSMentionError.missingArgument("url")
        }
        // Security: only http/https schemes. Block file://, ftp://, data:, javascript:,
        // and custom schemes that could exfiltrate local content via URLSession.
        let scheme = (url.scheme ?? "").lowercased()
        guard scheme == "http" || scheme == "https" else {
            throw FSMentionError.unknownTool("web scheme rejected: \(scheme)")
        }
        // SSRF block: refuse loopback / link-local / RFC1918 / cloud metadata IPs.
        if let host = url.host?.lowercased(), Self.isPrivateOrMetadataHost(host) {
            throw FSMentionError.unknownTool("private/internal host rejected: \(host)")
        }
        let queryText = args["queryText"] as? String ?? ""
        let alwaysRaw = UserDefaults.standard.bool(forKey: "chat.web.alwaysInjectRaw")

        var request = URLRequest(url: url)
        request.timeoutInterval = Self.webTimeout
        request.setValue("Zion/1.7 (+vibe)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw FSMentionError.httpError(http.statusCode)
        }
        let capped = data.count > Self.webByteCap ? data.prefix(Self.webByteCap) : data
        let body = String(data: capped, encoding: .utf8) ?? ""

        if alwaysRaw { return body }
        if body.utf8.count <= WebExcerptRetriever.directInjectThresholdBytes { return body }
        return WebExcerptRetriever.excerpt(html: body, query: queryText)
    }

    private func resolve(_ raw: String) throws -> URL {
        let candidate: URL
        if raw.hasPrefix("/") {
            candidate = URL(fileURLWithPath: raw)
        } else {
            candidate = repoURL.appendingPathComponent(raw)
        }
        let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
        // Security: prefix match must include the trailing separator so that
        // `/Users/me/repo-evil/x` cannot pass when `repoURL.path == /Users/me/repo`.
        let repoPath = repoURL.path
        let resolvedPath = resolved.path
        let isInside = (resolvedPath == repoPath) || resolvedPath.hasPrefix(repoPath + "/")
        guard isInside else {
            throw FSMentionError.pathTraversal(raw)
        }
        return resolved
    }

    /// Refuses loopback / link-local / RFC1918 / cloud metadata hosts to block SSRF
    /// from a malicious @web URL (e.g., `@web http://169.254.169.254/...` would otherwise
    /// hit the EC2 instance metadata service).
    static func isPrivateOrMetadataHost(_ host: String) -> Bool {
        let blocked: [String] = [
            "localhost", "0.0.0.0", "169.254.169.254"
        ]
        if blocked.contains(host) { return true }
        // IPv4 ranges: 10/8, 127/8, 192.168/16, 172.16/12, 169.254/16
        let parts = host.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4 {
            let (a, b) = (parts[0], parts[1])
            if a == 10 { return true }
            if a == 127 { return true }
            if a == 169 && b == 254 { return true }
            if a == 192 && b == 168 { return true }
            if a == 172 && (16...31).contains(b) { return true }
        }
        // IPv6 loopback / link-local prefix
        if host == "::1" || host.hasPrefix("fe80:") || host.hasPrefix("[::1]") { return true }
        return false
    }
}

enum FSMentionError: Error, LocalizedError {
    case unknownTool(String)
    case missingArgument(String)
    case pathTraversal(String)
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .unknownTool(let n):       return "Unknown tool: \(n)"
        case .missingArgument(let n):   return "Missing argument: \(n)"
        case .pathTraversal(let p):     return "Path traversal rejected: \(p)"
        case .httpError(let code):      return "HTTP \(code)"
        }
    }
}
