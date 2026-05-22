import Foundation

// MARK: - HarnessIntent

public enum HarnessIntent: Equatable {
    case lastCommit
    case currentChanges
    case recentHistory
    case status
    case fileContent(path: String)
    case commitDetails(sha: String)
}

// MARK: - IntentClassifier

public enum IntentClassifier {

    // MARK: Public

    /// Classifies a user text string into a HarnessIntent.
    /// Returns nil when confidence is low (conservative: false-positive worse than false-negative).
    public static func classify(_ text: String) -> HarnessIntent? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // fileContent — must run before generic keyword matching to capture path
        if let path = matchFileContent(trimmed) {
            return .fileContent(path: path)
        }

        // commitDetails — must run before lastCommit to capture SHA
        if let sha = matchCommitDetails(trimmed) {
            return .commitDetails(sha: sha)
        }

        if matches(trimmed, patterns: lastCommitPatterns) { return .lastCommit }
        if matches(trimmed, patterns: currentChangesPatterns) { return .currentChanges }
        if matches(trimmed, patterns: recentHistoryPatterns) { return .recentHistory }
        if matches(trimmed, patterns: statusPatterns) { return .status }

        return nil
    }

    // MARK: Private — patterns

    // .lastCommit (broad — also catches generic "show me code" without explicit path/sha)
    private static let lastCommitPatterns: [String] = [
        "last\\s+commit",
        "ultimo\\s+commit",
        "latest\\s+commit",
        "show\\s+(me\\s+the\\s+)?last\\s+commit",
        "show\\s+commit(?!\\s+[a-f0-9]{7,40})",   // "show commit" without a SHA
        "what\\s+was\\s+committed",
        "show\\s+(me\\s+)?(some\\s+|a\\s+|the\\s+|any\\s+)?(piece\\s+of\\s+)?code",
        "mostre?\\s+(uma\\s+|um\\s+)?(parte\\s+do\\s+|pedaco\\s+de\\s+|trecho\\s+de\\s+)?codigo",
        "mostra\\s+(uma\\s+)?linha",
        "give\\s+me\\s+(some\\s+|the\\s+|any\\s+)?code",
    ]

    // .currentChanges
    private static let currentChangesPatterns: [String] = [
        "current\\s+changes",
        "what\\s+changed",
        "que\\s+mudou",
        "uncommitted",
        "working\\s+tree\\s+changes",
        "my\\s+changes",
        "unstaged",
    ]

    // .recentHistory
    private static let recentHistoryPatterns: [String] = [
        "\\bhistory\\b",
        "\\bhistorico\\b",
        "recent\\s+commits",
        "\\bgit\\s+log\\b",
        "ultimos\\s+commits",
        "\\blog\\b",
    ]

    // .status — checked after recentHistory to avoid 'staged' in history match
    private static let statusPatterns: [String] = [
        "\\bstatus\\b",
        "working\\s+tree\\s+state",
        "\\bstaged\\b",
        "estado\\s+do\\s+repo",
        "what'?s\\s+staged",
    ]

    // MARK: Private — helpers

    private static func matches(_ text: String, patterns: [String]) -> Bool {
        let options: NSRegularExpression.Options = [.caseInsensitive]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            if regex.firstMatch(in: text, options: [], range: range) != nil {
                return true
            }
        }
        return false
    }

    /// Returns the file path if the text matches the fileContent pattern.
    private static func matchFileContent(_ text: String) -> String? {
        let pattern = #"(?:show|read|abre|veja|ver|explica|review)\s+(\S+\.\w+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1 else { return nil }
        let captureRange = match.range(at: 1)
        guard let swiftRange = Range(captureRange, in: text) else { return nil }
        return String(text[swiftRange])
    }

    /// Returns the commit SHA if the text matches the commitDetails pattern.
    private static func matchCommitDetails(_ text: String) -> String? {
        let pattern = #"(?:commit|sha)\s+([a-f0-9]{7,40})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1 else { return nil }
        let captureRange = match.range(at: 1)
        guard let swiftRange = Range(captureRange, in: text) else { return nil }
        return String(text[swiftRange])
    }
}
