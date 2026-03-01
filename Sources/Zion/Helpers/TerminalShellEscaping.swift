import Foundation

enum TerminalShellEscaping {
    static func quotePath(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func joinQuotedPaths(_ paths: [String]) -> String {
        paths
            .filter { !$0.isEmpty }
            .map(quotePath)
            .joined(separator: " ")
    }

    static func joinQuotedFileURLs(_ urls: [URL]) -> String {
        joinQuotedPaths(
            urls
                .filter { $0.isFileURL }
                .map(\.path)
        )
    }
}
