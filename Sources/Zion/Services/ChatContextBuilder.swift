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
    func gitContextHeader(repoURL: URL, branch: String) async -> String {
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
        // Safe path resolution — reject if outside repo
        let resolvedURL = repoURL
            .appendingPathComponent(path)
            .standardizedFileURL
        let repoStandardized = repoURL.standardizedFileURL

        guard resolvedURL.path.hasPrefix(repoStandardized.path + "/")
                || resolvedURL.path == repoStandardized.path else {
            return L10n("chat.slash.fileOutsideRepo")
        }

        do {
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
