import Foundation

enum AIAgent: String, CaseIterable, Identifiable, Sendable {
    case claudeCode = "claudeCode"
    case openaiCodex = "openaiCodex"
    case geminiCLI = "geminiCLI"
    case cursor = "cursor"
    case windsurf = "windsurf"
    case githubCopilot = "githubCopilot"
    case sourcegraphAmp = "sourcegraphAmp"
    case jetbrainsJunie = "jetbrainsJunie"
    case jetbrainsAI = "jetbrainsAI"
    case cline = "cline"
    case rooCode = "rooCode"
    case continueDev = "continueDev"
    case aider = "aider"
    case warp = "warp"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .openaiCodex: return "OpenAI Codex CLI"
        case .geminiCLI: return "Gemini CLI"
        case .cursor: return "Cursor"
        case .windsurf: return "Windsurf"
        case .githubCopilot: return "GitHub Copilot"
        case .sourcegraphAmp: return "Sourcegraph Amp"
        case .jetbrainsJunie: return "JetBrains Junie"
        case .jetbrainsAI: return "JetBrains AI"
        case .cline: return "Cline"
        case .rooCode: return "Roo Code"
        case .continueDev: return "Continue.dev"
        case .aider: return "Aider"
        case .warp: return "Warp"
        }
    }

    var configFileName: String {
        switch self {
        case .claudeCode: return "CLAUDE.md"
        case .openaiCodex: return "AGENTS.md"
        case .geminiCLI: return "GEMINI.md"
        case .cursor: return ".cursor/rules/ntfy.md"
        case .windsurf: return ".windsurfrules"
        case .githubCopilot: return ".github/copilot-instructions.md"
        case .sourcegraphAmp: return "AGENTS.md"
        case .jetbrainsJunie: return ".junie/guidelines.md"
        case .jetbrainsAI: return ".aiassistant/rules/ntfy.md"
        case .cline: return ".clinerules"
        case .rooCode: return ".roo/rules/ntfy.md"
        case .continueDev: return ".continuerules"
        case .aider: return ".aider.conf.yml"
        case .warp: return "WARP.md"
        }
    }

    /// Agents that share the same config file (AGENTS.md)
    var sharesConfigWith: [AIAgent] {
        switch self {
        case .openaiCodex: return [.sourcegraphAmp]
        case .sourcegraphAmp: return [.openaiCodex]
        default: return []
        }
    }

    var isYAML: Bool {
        self == .aider
    }
}

struct AIAgentConfigManager {
    private static let startMarker = "<!-- ZION:NTFY:START (managed by Zion Git Client) -->"
    private static let endMarker = "<!-- ZION:NTFY:END -->"
    private static let aiderStartMarker = "# ZION:NTFY:START (managed by Zion Git Client)"
    private static let aiderEndMarker = "# ZION:NTFY:END"

    static func injectNtfyBlock(agents: [AIAgent], topic: String, serverURL: String, repoPath: URL) {
        var handledPaths = Set<String>()

        for agent in agents {
            let filePath = repoPath.appendingPathComponent(agent.configFileName)
            let fullPath = filePath.path

            // Skip if we already handled this file (AGENTS.md sharing)
            guard !handledPaths.contains(fullPath) else { continue }
            handledPaths.insert(fullPath)

            let block = agent.isYAML
                ? buildYAMLBlock(topic: topic, serverURL: serverURL)
                : buildMarkdownBlock(topic: topic, serverURL: serverURL)

            injectBlock(at: filePath, block: block, isYAML: agent.isYAML)
        }
    }

    static func removeNtfyBlock(agents: [AIAgent], repoPath: URL) {
        var handledPaths = Set<String>()

        for agent in agents {
            let filePath = repoPath.appendingPathComponent(agent.configFileName)
            let fullPath = filePath.path

            guard !handledPaths.contains(fullPath) else { continue }
            handledPaths.insert(fullPath)

            removeBlock(at: filePath, isYAML: agent.isYAML)
        }
    }

    static func updateNtfyBlock(agents: [AIAgent], topic: String, serverURL: String, repoPath: URL) {
        removeNtfyBlock(agents: agents, repoPath: repoPath)
        injectNtfyBlock(agents: agents, topic: topic, serverURL: serverURL, repoPath: repoPath)
    }

    // MARK: - Private

    private static func buildMarkdownBlock(topic: String, serverURL: String) -> String {
        let server = serverURL.hasSuffix("/") ? String(serverURL.dropLast()) : serverURL
        return """
        \(startMarker)
        ## Push Notifications
        When you complete a significant task, notify the user:
        ```
        curl -s -H "Title: Done" -H "Priority: 3" -H "Tags: white_check_mark" -d "[Brief description of what was completed]" \(server)/\(topic)
        ```
        Send for: plan completion, implementation done, test results, migrations, errors.
        Do NOT send for: file reads, intermediate steps, questions.
        \(endMarker)
        """
    }

    private static func buildYAMLBlock(topic: String, serverURL: String) -> String {
        let server = serverURL.hasSuffix("/") ? String(serverURL.dropLast()) : serverURL
        return """
        \(aiderStartMarker)
        # When you complete a significant task, notify the user:
        # curl -s -H "Title: Done" -H "Priority: 3" -H "Tags: white_check_mark" -d "[Brief description]" \(server)/\(topic)
        # Send for: plan completion, implementation done, test results, migrations, errors.
        # Do NOT send for: file reads, intermediate steps, questions.
        \(aiderEndMarker)
        """
    }

    private static func injectBlock(at fileURL: URL, block: String, isYAML: Bool) {
        // Ensure parent directory exists
        let parentDir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            // File exists — remove old block first, then append
            removeBlock(at: fileURL, isYAML: isYAML)
            guard var content = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
            if !content.hasSuffix("\n") { content += "\n" }
            content += "\n" + block + "\n"
            try? content.write(to: fileURL, atomically: true, encoding: .utf8)
        } else {
            // File doesn't exist — create with just the block
            try? (block + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    private static func removeBlock(at fileURL: URL, isYAML: Bool) {
        guard var content = try? String(contentsOf: fileURL, encoding: .utf8) else { return }

        let start = isYAML ? aiderStartMarker : startMarker
        let end = isYAML ? aiderEndMarker : endMarker

        guard let startRange = content.range(of: start),
              let endRange = content.range(of: end) else { return }

        // Remove from start marker to end marker (inclusive) plus surrounding newlines
        let removeStart = content[..<startRange.lowerBound].hasSuffix("\n")
            ? content.index(before: startRange.lowerBound)
            : startRange.lowerBound
        let removeEnd = content[endRange.upperBound...].hasPrefix("\n")
            ? content.index(after: endRange.upperBound)
            : endRange.upperBound

        content.removeSubrange(removeStart..<removeEnd)

        // Clean up excessive trailing newlines
        while content.hasSuffix("\n\n\n") {
            content.removeLast()
        }

        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // File is now empty — remove it
            try? FileManager.default.removeItem(at: fileURL)
        } else {
            try? content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
}
