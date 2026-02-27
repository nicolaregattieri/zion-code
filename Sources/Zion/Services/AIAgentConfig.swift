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

    /// Global rules path relative to the user's home directory.
    /// Agents with `usesDedicatedFile == true` own the entire file (create/delete).
    /// Agents with `usesDedicatedFile == false` share a file and use marker-based block injection.
    var globalConfigRelativePath: String {
        switch self {
        case .claudeCode: return ".claude/rules/zion-ntfy/RULE.md"
        case .openaiCodex: return ".codex/rules/zion-ntfy.md"
        case .geminiCLI: return ".gemini/GEMINI.md"
        case .cursor: return ".cursor/rules/zion-ntfy.md"
        case .windsurf: return ".codeium/windsurf/memories/global_rules.md"
        case .githubCopilot: return ".config/github-copilot/zion-ntfy-instructions.md"
        case .sourcegraphAmp: return ".sourcegraph/rules/zion-ntfy.md"
        case .jetbrainsJunie: return ".junie/rules/zion-ntfy.md"
        case .jetbrainsAI: return ".aiassistant/rules/zion-ntfy.md"
        case .cline: return "Documents/Cline/Rules/zion-ntfy.md"
        case .rooCode: return ".roo/rules/zion-ntfy.md"
        case .continueDev: return ".continue/rules/zion-ntfy.md"
        case .aider: return ".aider.conf.yml"
        case .warp: return ".warp/rules/zion-ntfy.md"
        }
    }

    /// Absolute URL for this agent's global config file.
    var globalConfigURL: URL {
        globalConfigURL(baseDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// Absolute URL for this agent's global config file, relative to a custom base directory.
    func globalConfigURL(baseDirectory: URL) -> URL {
        baseDirectory.appendingPathComponent(globalConfigRelativePath)
    }

    /// The directory whose existence signals this agent is installed.
    var detectionRelativePath: String {
        switch self {
        case .claudeCode: return ".claude"
        case .openaiCodex: return ".codex"
        case .geminiCLI: return ".gemini"
        case .cursor: return ".cursor"
        case .windsurf: return ".codeium/windsurf"
        case .githubCopilot: return ".config/github-copilot"
        case .sourcegraphAmp: return ".sourcegraph"
        case .jetbrainsJunie: return ".junie"
        case .jetbrainsAI: return ".aiassistant"
        case .cline: return "Documents/Cline"
        case .rooCode: return ".roo"
        case .continueDev: return ".continue"
        case .aider: return ".aider.conf.yml" // file-based detection
        case .warp: return ".warp"
        }
    }

    /// Whether this agent is detected as installed on the system.
    var isInstalled: Bool {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(detectionRelativePath).path
        return FileManager.default.fileExists(atPath: path)
    }

    /// Agents that own their file entirely (create/delete the whole file).
    /// Shared-file agents (Gemini CLI, Windsurf, Aider) use block injection into an existing file.
    var usesDedicatedFile: Bool {
        switch self {
        case .geminiCLI, .windsurf, .aider: return false
        default: return true
        }
    }

    /// Old per-repo config file name (for cleanup migration).
    var legacyRepoConfigFileName: String {
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

    var isYAML: Bool {
        self == .aider
    }
}

struct AIAgentConfigManager {
    private static let startMarker = "<!-- ZION:NTFY:START (managed by Zion Git Client) -->"
    private static let endMarker = "<!-- ZION:NTFY:END -->"
    private static let aiderStartMarker = "# ZION:NTFY:START (managed by Zion Git Client)"
    private static let aiderEndMarker = "# ZION:NTFY:END"

    // MARK: - Public API (global rules)

    /// Install ntfy rule into the agent's global config directory.
    static func installGlobalRule(for agent: AIAgent) {
        installGlobalRule(for: agent, baseDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// Install ntfy rule using a custom base directory (for testing).
    static func installGlobalRule(for agent: AIAgent, baseDirectory: URL) {
        let fileURL = agent.globalConfigURL(baseDirectory: baseDirectory)
        // Refuse to write through symlinks
        guard !isSymlink(at: fileURL.path) else { return }
        let block = agent.isYAML ? buildYAMLBlock() : buildMarkdownBlock()

        if agent.usesDedicatedFile {
            // Own the whole file — create parent dir and write
            let parentDir = fileURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            try? block.write(to: fileURL, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } else {
            injectBlock(at: fileURL, block: block, isYAML: agent.isYAML)
        }
    }

    /// Remove ntfy rule from the agent's global config directory.
    static func removeGlobalRule(for agent: AIAgent) {
        removeGlobalRule(for: agent, baseDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// Remove ntfy rule using a custom base directory (for testing).
    static func removeGlobalRule(for agent: AIAgent, baseDirectory: URL) {
        let fileURL = agent.globalConfigURL(baseDirectory: baseDirectory)

        if agent.usesDedicatedFile {
            // Delete the whole file; also remove parent dir if now empty
            try? FileManager.default.removeItem(at: fileURL)
            let parentDir = fileURL.deletingLastPathComponent()
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: parentDir.path), contents.isEmpty {
                try? FileManager.default.removeItem(at: parentDir)
            }
        } else {
            removeBlock(at: fileURL, isYAML: agent.isYAML)
        }
    }

    /// Check if the global rule is currently installed for this agent.
    static func isGlobalRuleInstalled(for agent: AIAgent) -> Bool {
        isGlobalRuleInstalled(for: agent, baseDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// Check if the global rule is installed using a custom base directory (for testing).
    static func isGlobalRuleInstalled(for agent: AIAgent, baseDirectory: URL) -> Bool {
        let fileURL = agent.globalConfigURL(baseDirectory: baseDirectory)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return false }

        if agent.usesDedicatedFile {
            // If the dedicated file exists, the rule is installed
            return true
        } else {
            // Check for our marker block
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return false }
            let start = agent.isYAML ? aiderStartMarker : startMarker
            return content.contains(start)
        }
    }

    // MARK: - Legacy per-repo cleanup

    /// Remove old per-repo ntfy blocks from a repository (migration).
    static func removeLegacyRepoBlocks(repoPath: URL) {
        var handledPaths = Set<String>()

        for agent in AIAgent.allCases {
            let filePath = repoPath.appendingPathComponent(agent.legacyRepoConfigFileName)
            let fullPath = filePath.path

            guard !handledPaths.contains(fullPath) else { continue }
            handledPaths.insert(fullPath)

            removeBlock(at: filePath, isYAML: agent.isYAML)
        }
    }

    // MARK: - Private

    private static func isSymlink(at path: String) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return false }
        let attrs = try? fm.attributesOfItem(atPath: path)
        return attrs?[.type] as? FileAttributeType == .typeSymbolicLink
    }

    private static func buildMarkdownBlock() -> String {
        """
        \(startMarker)
        ## Push Notifications
        When you complete a significant task, notify the user:
        1. Read `~/.config/ntfy/config.json` to get `topic` and `server`
        2. Send: `curl -s -H "Title: Done" -H "Priority: 3" -H "Tags: white_check_mark" -d "[Brief description]" '{server}/{topic}'`
        Send for: plan completion, implementation done, test results, migrations, errors.
        Do NOT send for: file reads, intermediate steps, questions.
        \(endMarker)
        """
    }

    private static func buildYAMLBlock() -> String {
        """
        \(aiderStartMarker)
        # When you complete a significant task, notify the user:
        # 1. Read ~/.config/ntfy/config.json to get topic and server
        # 2. Run: curl -s -H "Title: Done" -H "Priority: 3" -H "Tags: white_check_mark" -d "[Brief description]" '{server}/{topic}'
        # Send for: plan completion, implementation done, test results, migrations, errors.
        # Do NOT send for: file reads, intermediate steps, questions.
        \(aiderEndMarker)
        """
    }

    private static func injectBlock(at fileURL: URL, block: String, isYAML: Bool) {
        // Refuse to write through symlinks
        guard !isSymlink(at: fileURL.path) else { return }
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
