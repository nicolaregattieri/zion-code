import Foundation

enum EditorHelpers {

    /// Build a regex from search options (shared between find bar and editor coordinator)
    static func buildSearchRegex(
        query: String,
        matchCase: Bool,
        isRegex: Bool,
        wholeWord: Bool
    ) -> NSRegularExpression? {
        guard !query.isEmpty else { return nil }
        var pattern: String
        if isRegex {
            pattern = query
        } else {
            pattern = NSRegularExpression.escapedPattern(for: query)
        }
        if wholeWord {
            pattern = "\\b\(pattern)\\b"
        }
        var options: NSRegularExpression.Options = []
        if !matchCase { options.insert(.caseInsensitive) }
        return try? NSRegularExpression(pattern: pattern, options: options)
    }

    /// Strip trailing spaces and tabs from each line
    static func trimTrailingWhitespace(_ content: String) -> String {
        content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                var s = String(line)
                while s.last == " " || s.last == "\t" { s.removeLast() }
                return s
            }
            .joined(separator: "\n")
    }

    /// Recursively filter a file tree, keeping files whose name contains the query
    /// and directories that have matching descendants.
    static func filterFileTree(_ item: FileItem, query: String) -> FileItem? {
        if !item.isDirectory {
            return item.name.lowercased().contains(query) ? item : nil
        }
        let filteredChildren = (item.children ?? []).compactMap { filterFileTree($0, query: query) }
        if filteredChildren.isEmpty && !item.name.lowercased().contains(query) { return nil }
        return FileItem(
            url: item.url,
            isDirectory: true,
            children: filteredChildren.isEmpty ? nil : filteredChildren,
            isGitIgnored: item.isGitIgnored
        )
    }
}
