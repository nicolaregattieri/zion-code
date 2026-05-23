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
        var request = URLRequest(url: url)
        request.timeoutInterval = Self.webTimeout
        request.setValue("Zion/1.7 (+vibe)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw FSMentionError.httpError(http.statusCode)
        }
        let capped = data.count > Self.webByteCap ? data.prefix(Self.webByteCap) : data
        return String(data: capped, encoding: .utf8) ?? ""
    }

    private func resolve(_ raw: String) throws -> URL {
        let candidate: URL
        if raw.hasPrefix("/") {
            candidate = URL(fileURLWithPath: raw)
        } else {
            candidate = repoURL.appendingPathComponent(raw)
        }
        let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(repoURL.path) else {
            throw FSMentionError.pathTraversal(raw)
        }
        return resolved
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
