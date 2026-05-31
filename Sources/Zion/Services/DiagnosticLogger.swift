import Foundation

enum LogLevel: String, CaseIterable {
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
    case git = "GIT"
    case ai = "AI"
}

struct LogEntry {
    let timestamp: Date
    let level: LogLevel
    let message: String
    let context: String?
    let source: String?
}

@MainActor
final class DiagnosticLogger {
    static let shared = DiagnosticLogger()

    private var entries: [LogEntry] = []
    private let maxEntries = 500
    private let maxSanitizedLineLength = 200
    private let timeFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"
        return dateFormatter
    }()

    /// Disk log path: `~/Library/Logs/Zion/diagnostic.log`. Created on first
    /// write. Each `log()` call appends a line so users (and Claude in chat)
    /// can `tail -f` it to debug provider routing / health failures live.
    private static let diskLogURL: URL = {
        let logs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Zion", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("diagnostic.log")
    }()
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {}

    func log(_ level: LogLevel, _ message: String, context: String? = nil, source: String = #function) {
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            message: message,
            context: context,
            source: source
        )
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        appendToDisk(entry)
    }

    /// Best-effort append to the on-disk log. Failures are swallowed — disk
    /// I/O must never break the in-memory buffer that the export UI relies on.
    private func appendToDisk(_ entry: LogEntry) {
        let ts = isoFormatter.string(from: entry.timestamp)
        var line = "[\(ts)] [\(entry.level.rawValue)] \(sanitize(entry.message))"
        if let ctx = entry.context { line += " | ctx: \(sanitize(ctx))" }
        if let src = entry.source { line += " | source: \(src)" }
        line += "\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = Self.diskLogURL
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    func exportLog() -> String {
        let header = buildHeader()
        let body = entries.map { entry in
            var line = "[\(timeFormatter.string(from: entry.timestamp))] [\(entry.level.rawValue)] \(sanitize(entry.message))"
            if let ctx = entry.context {
                line += " | ctx: \(sanitize(ctx))"
            }
            if let src = entry.source {
                line += " | source: \(src)"
            }
            return line
        }.joined(separator: "\n")

        return "\(header)\n\n\(body)"
    }

    func clear() {
        entries.removeAll()
    }

    var entryCount: Int { entries.count }

    // MARK: - Private

    private func buildHeader() -> String {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let dateStr = isoFormatter.string(from: Date())

        return """
        === Zion Diagnostic Log ===
        macOS: \(osVersion) | Date: \(dateStr)
        Entries: \(entries.count)
        """
    }

    private func sanitize(_ text: String) -> String {
        var result = text

        // Strip home directory
        let home = NSHomeDirectory()
        result = result.replacingOccurrences(of: home, with: "~")

        // Strip API keys and tokens
        result = result.replacingOccurrences(
            of: "sk-ant-[A-Za-z0-9_-]+",
            with: "[REDACTED]",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "sk-[A-Za-z0-9_-]{20,}",
            with: "[REDACTED]",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "ghp_[A-Za-z0-9]{20,}",
            with: "[REDACTED]",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "github_pat_[A-Za-z0-9_]{20,}",
            with: "[REDACTED]",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "AIza[0-9A-Za-z\\-_]{20,}",
            with: "[REDACTED]",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "(?i)Bearer\\s+[A-Za-z0-9._\\-~+/]+=*",
            with: "Bearer [REDACTED]",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "(?i)(https?://)[^/@\\s]+@",
            with: "$1[REDACTED]@",
            options: .regularExpression
        )

        // Strip ntfy topics. The topic doubles as the bearer secret on public
        // ntfy servers — anyone reading an exported diagnostic log could
        // subscribe to or publish into the user's channel. Defense-in-depth
        // alongside `NtfyClient.redactTopic` at the call site.
        result = result.replacingOccurrences(
            of: "/zion-code-[A-Za-z0-9._-]+",
            with: "/[REDACTED]",
            options: .regularExpression
        )

        // Truncate very long lines
        if result.count > maxSanitizedLineLength {
            result = String(result.prefix(maxSanitizedLineLength)) + "...[truncated]"
        }

        return result
    }
}
