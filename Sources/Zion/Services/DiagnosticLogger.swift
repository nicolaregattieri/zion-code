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
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
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

        // Strip API keys (sk-ant-*, sk-*)
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

        // Truncate very long lines
        if result.count > 500 {
            result = String(result.prefix(500)) + "...[truncated]"
        }

        return result
    }
}
