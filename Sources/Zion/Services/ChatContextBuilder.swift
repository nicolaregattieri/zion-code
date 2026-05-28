import Foundation

/// Builds git context strings for injection into chat messages.
struct ChatContextBuilder {
    let worker: RepositoryWorker

    // MARK: - Slash Command Parsing

    enum SlashCommand: Equatable {
        case diff
        case log
        case status
        case file(path: String)
        case commit(sha: String)
    }

    /// Pure parser — line-anchored so inline slashes inside URLs do not match.
    static func parseSlashCommand(_ line: String) -> SlashCommand? {
        // Pattern: optional leading whitespace, slash, command, optional whitespace + arg
        let pattern = #"^\s*/(diff|log|status|file|commit)(\s+(.+))?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: line,
                range: NSRange(line.startIndex..., in: line)
              ) else {
            return nil
        }

        let commandRange = Range(match.range(at: 1), in: line)
        let command = commandRange.map { String(line[$0]) } ?? ""

        let argRange = Range(match.range(at: 3), in: line)
        let arg = argRange.map { String(line[$0]).trimmingCharacters(in: .whitespaces) }
        let trimmedArg = arg.flatMap { $0.isEmpty ? nil : $0 }

        switch command {
        case "diff":
            return .diff
        case "log":
            return .log
        case "status":
            return .status
        case "file":
            guard let path = trimmedArg else { return nil }
            return .file(path: path)
        case "commit":
            guard let sha = trimmedArg else { return nil }
            return .commit(sha: sha)
        default:
            return nil
        }
    }

    // MARK: - Context Header

    /// Produces a formatted header with repo name, branch, HEAD SHA, and uncommitted count.
    /// Suffixes any imported project guidance (CLAUDE.md / AGENTS.md / etc.)
    /// so Zion Talks inherits the conventions the project already documented
    /// for other LLMs.
    func gitContextHeader(repoURL: URL, branch: String) async -> String {
        let header = await rawGitContextHeader(repoURL: repoURL, branch: branch)
        let guidance = await MainActor.run {
            ProjectGuidanceImporter.shared.importedContent(for: repoURL)
        }
        // Global system prompt — written once in Settings → AI, applied to
        // every Zion Talks turn across every repo. Sits between the git
        // header and the project guidance so the LLM reads "what the user
        // always wants" before "what this repo specifically documents".
        let globalPrompt = (UserDefaults.standard.string(forKey: "chat.globalSystemPrompt") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var sections = [header]
        if !globalPrompt.isEmpty {
            sections.append("## Global guidance (user)\n\n" + globalPrompt)
        }
        if !guidance.isEmpty {
            sections.append("## Project guidance (imported)\n\n" + guidance)
        }
        return sections.joined(separator: "\n\n")
    }

    private func rawGitContextHeader(repoURL: URL, branch: String) async -> String {
        let repoName = repoURL.lastPathComponent

        let sha: String
        do {
            sha = try await worker.runAction(
                args: ["rev-parse", "--short=7", "HEAD"],
                in: repoURL
            )
        } catch {
            sha = L10n("chat.head.unknown")
        }

        let uncommittedCount: Int
        do {
            let statusOutput = try await worker.runAction(
                args: ["status", "--porcelain"],
                in: repoURL
            )
            let lines = statusOutput
                .components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            uncommittedCount = lines.count
        } catch {
            uncommittedCount = 0
        }

        return L10n("chat.contextHeader", repoName, branch, sha, uncommittedCount)
    }

    // MARK: - Slash Command Expansion

    /// Scans text line-by-line; replaces slash command lines with appended fenced git output.
    func expandSlashCommands(_ text: String, repoURL: URL) async -> String {
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []

        for line in lines {
            guard let cmd = Self.parseSlashCommand(line) else {
                result.append(line)
                continue
            }
            let block = await expandCommand(cmd, repoURL: repoURL)
            result.append(line)
            result.append(block)
        }

        return result.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    private func expandCommand(_ cmd: SlashCommand, repoURL: URL) async -> String {
        switch cmd {
        case .diff:
            return await runFenced(
                args: ["diff"],
                repoURL: repoURL,
                language: "diff",
                maxLength: AILimits.maxDiffContentLength,
                emptyFallback: L10n("chat.slash.empty.diff")
            )

        case .log:
            return await runFenced(
                args: ["log", "--oneline", "-20"],
                repoURL: repoURL,
                language: "text",
                maxLength: AILimits.maxCommitLogLength
            )

        case .status:
            return await runFenced(
                args: ["status", "--short"],
                repoURL: repoURL,
                language: "text",
                maxLength: AILimits.maxDiffContentLength
            )

        case .file(let path):
            return await expandFile(path: path, repoURL: repoURL)

        case .commit(let sha):
            return await runFenced(
                args: ["show", sha],
                repoURL: repoURL,
                language: "diff",
                maxLength: AILimits.maxCommitLogLength
            )
        }
    }

    private func runFenced(
        args: [String],
        repoURL: URL,
        language: String,
        maxLength: Int,
        emptyFallback: String? = nil
    ) async -> String {
        let output: String
        do {
            output = try await worker.runAction(args: args, in: repoURL)
        } catch {
            output = ""
        }

        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let fallback = emptyFallback {
                return fallback
            }
            return fencedBlock("", language: language)
        }

        let truncated = output.count > maxLength
            ? String(output.prefix(maxLength))
            : output

        return fencedBlock(truncated, language: language)
    }

    private func expandFile(path: String, repoURL: URL) async -> String {
        do {
            let resolvedURL = try RepositoryWorker.resolveInsideRepo(
                path: path,
                repositoryURL: repoURL,
                op: "read"
            )
            let content = try String(contentsOf: resolvedURL, encoding: .utf8)
            let truncated = content.count > AILimits.maxFileContentPreviewLength
                ? String(content.prefix(AILimits.maxFileContentPreviewLength))
                : content
            return fencedBlock(truncated, language: "text")
        } catch {
            return L10n("chat.slash.fileOutsideRepo")
        }
    }

    private func fencedBlock(_ content: String, language: String) -> String {
        "```\(language)\n\(content)\n```"
    }
}

// MARK: - /help payload builder

extension ChatContextBuilder {
    /// Builds a static HelpCardPayload snapshot from live registries at /help time.
    @MainActor
    func buildHelpPayload(
        registry: SlashCommandRegistry,
        skillIndex: SkillIndex,
        mcpStore: MCPRegistryStore? = nil
    ) -> HelpCardPayload {
        // Built-in commands
        let builtIn = registry.all
            .filter { $0.source == .builtIn }
            .map { item in
                HelpCardPayload.HelpCardItem(
                    id: item.id,
                    label: item.name + (item.argHint.map { " " + $0 } ?? ""),
                    description: item.description
                )
            }

        // Project skills
        let projectSkills = skillIndex.skills
            .filter { $0.scope == .project }
            .map { HelpCardPayload.HelpCardItem(id: $0.id, label: "/" + $0.id, description: $0.description) }

        // User skills
        let userSkills = skillIndex.skills
            .filter { $0.scope == .user }
            .map { HelpCardPayload.HelpCardItem(id: $0.id, label: "/" + $0.id, description: $0.description) }

        // @ mentions — static list
        let mentions: [HelpCardPayload.HelpCardItem] = [
            .init(id: "file", label: "@file <path>", description: L10n("chat.help.mention.file")),
            .init(id: "folder", label: "@folder <path>", description: L10n("mention.folder.token")),
            .init(id: "selection", label: "@selection", description: L10n("chat.help.mention.selection")),
            .init(id: "web", label: "@web <url>", description: L10n("chat.help.mention.web")),
            .init(id: "diff", label: "@diff", description: L10n("mention.diff.token")),
            .init(id: "pr", label: "@pr", description: L10n("mention.pr.token")),
            .init(id: "code", label: "@code <query>", description: L10n("mention.code.token"))
        ]

        // MCP tools — from store if available
        let mcpTools: [HelpCardPayload.HelpCardItem] = mcpStore.map { store in
            store.servers.map { server in
                HelpCardPayload.HelpCardItem(
                    id: server.id,
                    label: server.id,
                    description: L10n("chat.help.mcpServer.description")
                )
            }
        } ?? []

        // Keyboard shortcuts
        let shortcuts: [HelpCardPayload.HelpCardItem] = [
            .init(id: "send", label: "\u{23CE}", description: L10n("chat.help.shortcut.send")),
            .init(id: "newline", label: "\u{21E7}\u{23CE}", description: L10n("chat.help.shortcut.newline")),
            .init(id: "stop", label: "\u{2303}C", description: L10n("chat.help.shortcut.stop")),
            .init(id: "history", label: "\u{2318}L", description: L10n("chat.help.shortcut.history"))
        ]

        return HelpCardPayload(
            builtInItems: builtIn,
            projectSkills: projectSkills,
            userSkills: userSkills,
            mentions: mentions,
            mcpTools: mcpTools,
            shortcuts: shortcuts
        )
    }
}
