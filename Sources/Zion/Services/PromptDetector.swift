import Foundation

@MainActor
enum PromptDetector {
    struct Detection: Sendable {
        let label: String
        let promptText: String
    }

    private static let patterns: [(regex: String, label: String)] = [
        // Generic Y/N prompts
        (#"\[Y/n\]"#, "Confirm (Y/n)"),
        (#"\[y/N\]"#, "Confirm (y/N)"),
        (#"\(y/n\)"#, "Confirm (y/n)"),
        (#"\(Y/n\)"#, "Confirm (Y/n)"),
        (#"Do you want to proceed\?"#, "Proceed?"),
        (#"Do you want to continue\?"#, "Continue?"),

        // Claude Code
        (#"Allow\?"#, "Allow?"),
        (#"Do you want to"#, "Claude prompt"),

        // Aider
        (#"Add .+ to the chat\?"#, "Aider: Add to chat?"),

        // Generic
        (#"Press Enter to continue"#, "Press Enter"),
        (#"Enter passphrase"#, "Passphrase required"),
        (#"Are you sure\?"#, "Are you sure?"),
        (#"\? \(yes/no\)"#, "Confirm (yes/no)"),
    ]

    private static var recentHashes: Set<Int> = []
    private static let maxHashHistory = 50

    static func detect(in text: String) -> Detection? {
        for (pattern, label) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
                continue
            }

            let matchedRange = Range(match.range, in: text)!
            let promptText = String(text[matchedRange])

            // Dedup by hash to avoid spamming
            let hash = promptText.hashValue
            if recentHashes.contains(hash) { return nil }

            recentHashes.insert(hash)
            if recentHashes.count > maxHashHistory {
                recentHashes.removeFirst()
            }

            return Detection(label: label, promptText: promptText)
        }
        return nil
    }

    static func resetDedup() {
        recentHashes.removeAll()
    }
}
