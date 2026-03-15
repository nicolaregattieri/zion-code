import Foundation
import SwiftUI

extension RepositoryViewModel {

    // MARK: - AI Pending Changes Summary

    func summarizePendingChanges() {
        guard let url = repositoryURL, isAIConfigured, !uncommittedChanges.isEmpty else { return }
        beginPendingChangesSummaryRequest()

        let fileList = uncommittedChanges.joined(separator: "\n")
        pendingSummaryTask = Task { [weak self] in
            guard let self else { return }
            do {
                let diffStat = try await worker.runGitCommand(in: url, args: ["diff", "--stat"])
                try Task.checkCancellation()
                let summary = try await aiClient.summarizePendingChanges(
                    diffStat: diffStat,
                    fileList: fileList,
                    provider: aiProvider,
                    apiKey: aiAPIKey,
                    mode: aiMode
                )
                try Task.checkCancellation()
                applyPendingChangesSummary(summary)
            } catch is CancellationError {
                return
            } catch {
                handlePendingChangesSummaryFailure(error)
                logger.log(.error, "AI pending changes summary failed: \(error.localizedDescription)", context: aiProvider.rawValue, source: #function)
            }
        }
    }

    // MARK: - AI Commit Message

    func suggestCommitMessage() {
        guard let url = repositoryURL else { return }

        aiTask?.cancel()
        aiTask = Task {
            isGeneratingAIMessage = true
            defer { isGeneratingAIMessage = false }

            do {
                aiQuotaExceeded = false
                let diffStatOutput = try await worker.runAction(args: ["diff", "--cached", "--stat"], in: url)
                var diffStat = diffStatOutput
                let status = try await worker.runAction(args: ["status", "--porcelain"], in: url)

                logger.log(.ai, "AI Configured: \(isAIConfigured), Provider: \(aiProvider.rawValue), Key length: \(aiAPIKey.count)")

                if isAIConfigured {
                    logger.log(.ai, "Requesting commit message", context: aiProvider.rawValue)
                    var diff = try await worker.runAction(args: ["diff", "--cached"], in: url)

                    // If nothing is staged, we're likely in a "Quick Commit" flow.
                    // Provide the unstaged diff to the AI so it has context.
                    if diff.isEmpty && !status.isEmpty {
                        logger.log(.ai, "Staged diff is empty, trying unstaged diff for context")
                        diff = try await worker.runAction(args: ["diff"], in: url)
                        diffStat = try await worker.runAction(args: ["diff", "--stat"], in: url)

                        // If still empty (e.g. only untracked files), provide the status list AND some content
                        if diff.isEmpty {
                            logger.log(.ai, "Unstaged diff also empty, reading untracked files content")
                            var untrackedContext = "New files (untracked):\n\(status)\n\nFile contents summary:\n"
                            let untrackedFiles = status
                                .split(separator: "\n")
                                .compactMap { RepositoryViewModel.parsePorcelainStatusLine(String($0)) }
                                .filter(\.isUntracked)
                                .map(\.path)

                            for file in untrackedFiles.prefix(Constants.Limits.maxUntrackedFilesForContext) {
                                if let content = try? await worker.runAction(args: ["show", ":\(file)"], in: url) {
                                    untrackedContext += "--- \(file) ---\n\(content.prefix(Constants.Limits.maxFileContentPreviewLength))\n"
                                } else if let localContent = try? String(contentsOf: url.appendingPathComponent(file), encoding: .utf8) {
                                    untrackedContext += "--- \(file) ---\n\(localContent.prefix(Constants.Limits.maxFileContentPreviewLength))\n"
                                }
                            }
                            diff = untrackedContext
                        }
                    }

                    if diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        logger.log(.ai, "No changes detected at all, skipping AI")
                        suggestedCommitMessage = ""
                        return
                    }

                    let logOutput = try? await worker.runAction(args: ["log", "--oneline", "-10"], in: url)
                    let recentMessages = (logOutput ?? "").split(separator: "\n").map { line in
                        let parts = line.split(separator: " ", maxSplits: 1)
                        return parts.count > 1 ? String(parts[1]) : String(line)
                    }

                    let message = try await aiClient.generateCommitMessage(
                        diff: diff,
                        diffStat: diffStat,
                        recentMessages: recentMessages,
                        branchName: currentBranch,
                        provider: aiProvider,
                        apiKey: aiAPIKey,
                        style: commitMessageStyle,
                        mode: aiMode,
                        repoContext: buildRepoContext(
                            fileHints: uncommittedChanges,
                            recentMessages: recentMessages
                        )
                    )
                    logger.log(.ai, "Commit message generated OK")
                    suggestedCommitMessage = message
                } else {
                    suggestedCommitMessage = Self.generateCommitMessage(diffStat: diffStat, status: status)
                }
            } catch {
                if let aiErr = error as? AIError, case .quotaExceeded = aiErr {
                    aiQuotaExceeded = true
                } else if let aiErr = error as? AIError, case .temporarilyUnavailable = aiErr {
                    statusMessage = L10n("IA temporariamente indisponivel. Sugestao local aplicada.")
                }
                logger.log(.error, "AI commit message failed: \(error.localizedDescription)", context: aiProvider.rawValue, source: #function)
                // Fallback to heuristic on AI failure
                if let url = repositoryURL,
                   let diffStat = try? await worker.runAction(args: ["diff", "--cached", "--stat"], in: url),
                   let status = try? await worker.runAction(args: ["status", "--porcelain"], in: url) {
                    suggestedCommitMessage = Self.generateCommitMessage(diffStat: diffStat, status: status)
                } else {
                    suggestedCommitMessage = ""
                }
            }
        }
    }

    func suggestPRDescription(baseBranch: String) async -> (title: String, body: String)? {
        guard let url = repositoryURL, isAIConfigured else { return nil }

        isGeneratingAIMessage = true
        defer { isGeneratingAIMessage = false }

        do {
            logger.log(.ai, "Requesting PR description", context: aiProvider.rawValue)
            let commitLog = try await worker.runAction(
                args: ["log", "--oneline", "\(baseBranch)..HEAD"],
                in: url
            )
            let diffStat = try await worker.runAction(
                args: ["diff", "--stat", "\(baseBranch)..HEAD"],
                in: url
            )
            let result = try await aiClient.generatePRDescription(
                commitLog: commitLog,
                diffStat: diffStat,
                branchName: currentBranch,
                baseBranch: baseBranch,
                provider: aiProvider,
                apiKey: aiAPIKey,
                mode: aiMode,
                repoContext: buildRepoContext(
                    fileHints: Self.parseFileHints(fromDiffStat: diffStat),
                    recentMessages: Self.parseCommitSubjects(fromLog: commitLog),
                    extraNotes: [
                        "source branch: \(currentBranch)",
                        "base branch: \(baseBranch)"
                    ]
                )
            )
            logger.log(.ai, "PR description generated OK")
            return result
        } catch {
            logger.log(.error, "AI PR description failed: \(error.localizedDescription)", context: aiProvider.rawValue, source: #function)
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Release Changelog

    func generateReleaseChangelog() async -> String? {
        guard let url = repositoryURL,
              currentBranch.hasPrefix("release/") else { return nil }

        let version = String(currentBranch.dropFirst("release/".count))
        let prevTag = await worker.previousReleaseTag(in: url)

        // Build git log args: scoped to prevTag..HEAD if a tag exists, otherwise full history
        var logArgs = ["log", "--oneline", "--no-merges"]
        if let prevTag {
            logArgs.append("\(prevTag)..HEAD")
        }

        guard let commitLog = try? await worker.runAction(args: logArgs, in: url),
              !commitLog.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let bullets = commitLog
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line in
                // Strip the short hash prefix (e.g. "abc1234 message" -> "message")
                let message = line.drop(while: { !$0.isWhitespace }).dropFirst()
                return "* \(message)"
            }
            .joined(separator: "\n")

        var result = "## \(L10n("pr.release.whatsChanged"))\n\(bullets)"
        if let prevTag {
            result += "\n\n**\(L10n("pr.release.fullChangelog"))**: \(prevTag)...v\(version)"
        }
        return result
    }

    func suggestStashMessage() {
        guard let url = repositoryURL, isAIConfigured else { return }

        aiTask?.cancel()
        aiTask = Task {
            isGeneratingAIMessage = true
            defer { isGeneratingAIMessage = false }

            do {
                logger.log(.ai, "Requesting stash message", context: aiProvider.rawValue)
                let diff = try await worker.runAction(args: ["diff"], in: url)
                let diffStat = try await worker.runAction(args: ["diff", "--stat"], in: url)
                let message = try await aiClient.generateStashMessage(
                    diff: diff,
                    diffStat: diffStat,
                    provider: aiProvider,
                    apiKey: aiAPIKey,
                    mode: aiMode
                )
                logger.log(.ai, "Stash message generated OK")
                stashMessageInput = message
            } catch {
                logger.log(.error, "AI stash message failed: \(error.localizedDescription)", context: aiProvider.rawValue, source: #function)
                lastError = error.localizedDescription
            }
        }
    }

    func explainFileDiff(fileName: String, diff: String) {
        guard isAIConfigured else { return }

        aiTask?.cancel()
        aiTask = Task {
            isGeneratingAIMessage = true
            defer { isGeneratingAIMessage = false }

            do {
                logger.log(.ai, "Requesting diff explanation", context: "\(aiProvider.rawValue): \(fileName)")
                let explanation = try await aiClient.explainDiff(
                    fileDiff: diff,
                    fileName: fileName,
                    provider: aiProvider,
                    apiKey: aiAPIKey,
                    mode: aiMode
                )
                logger.log(.ai, "Diff explanation generated OK")
                aiDiffExplanation = explanation
            } catch {
                logger.log(.error, "AI diff explanation failed: \(error.localizedDescription)", context: aiProvider.rawValue, source: #function)
                aiDiffExplanation = ""
                lastError = error.localizedDescription
            }
        }
    }

    // MARK: - Detailed Diff Explanation (Phase 2)

    func explainDiffDetailed(fileName: String, diff: String) {
        guard isAIConfigured else { return }

        explainDiffTask?.cancel()
        explainDiffTask = Task {
            isExplainingDiff = true
            defer { isExplainingDiff = false }

            do {
                let explanation = try await aiClient.explainDiffDetailed(
                    fileDiff: diff,
                    fileName: fileName,
                    provider: aiProvider,
                    apiKey: aiAPIKey,
                    mode: aiMode,
                    repoContext: buildRepoContext(fileHints: [fileName])
                )
                currentDiffExplanation = explanation
            } catch {
                currentDiffExplanation = nil
                lastError = error.localizedDescription
            }
        }
    }

    // MARK: - AI Smart Conflict Resolution

    func resolveConflictWithAI(region: ConflictRegion, fileName: String) {
        guard let url = repositoryURL, isAIConfigured else { return }

        aiTask?.cancel()
        aiTask = Task {
            isGeneratingAIMessage = true
            aiConflictResolvingRegionID = region.id
            defer {
                isGeneratingAIMessage = false
                aiConflictResolvingRegionID = nil
            }

            do {
                logger.log(.ai, "Requesting conflict resolution", context: "\(aiProvider.rawValue): \(fileName)")
                // Get surrounding context from the file
                var context = ""
                if let fileContent = try? String(contentsOf: url.appendingPathComponent(fileName), encoding: .utf8) {
                    context = String(fileContent.prefix(3000))
                }

                let resolved = try await aiClient.resolveConflict(
                    oursLines: region.oursLines,
                    theirsLines: region.theirsLines,
                    oursLabel: region.oursLabel,
                    theirsLabel: region.theirsLabel,
                    surroundingContext: context,
                    fileName: fileName,
                    provider: aiProvider,
                    apiKey: aiAPIKey,
                    mode: aiMode,
                    repoContext: buildRepoContext(fileHints: [fileName])
                )
                logger.log(.ai, "Conflict resolution generated OK")
                aiConflictResolutionRegionID = region.id
                aiConflictResolution = resolved
            } catch {
                logger.log(.error, "AI conflict resolution failed: \(error.localizedDescription)", context: aiProvider.rawValue, source: #function)
                aiConflictResolutionRegionID = nil
                aiConflictResolution = ""
                lastError = error.localizedDescription
            }
        }
    }

    func consumeAIConflictResolution(for regionID: UUID) -> String? {
        guard aiConflictResolutionRegionID == regionID, !aiConflictResolution.isEmpty else { return nil }
        let resolved = aiConflictResolution
        aiConflictResolution = ""
        aiConflictResolutionRegionID = nil
        return resolved
    }

    // MARK: - Heuristic Commit Message

    static func generateCommitMessage(diffStat: String, status: String) -> String {
        let lines = status.split(separator: "\n").map(String.init)
        guard !lines.isEmpty else { return "" }

        var added = 0, modified = 0, deleted = 0
        var paths: [String] = []
        for line in lines {
            guard let entry = RepositoryViewModel.parsePorcelainStatusLine(line) else { continue }
            let indexStatus = entry.indexStatus
            let workTreeStatus = entry.worktreeStatus
            let file = entry.path

            paths.append(file)

            if indexStatus == "A" || indexStatus == "?" {
                added += 1
            } else if workTreeStatus == "M" || indexStatus == "M" {
                modified += 1
            } else if workTreeStatus == "D" || indexStatus == "D" {
                deleted += 1
            } else {
                modified += 1
            }
        }

        let scope: String
        let commonComponents = paths.compactMap { $0.split(separator: "/").dropLast().first }.map(String.init)
        if let most = commonComponents.mostFrequent() {
            scope = "(\(most))"
        } else {
            scope = ""
        }

        let type: String
        if added > 0 && modified == 0 && deleted == 0 {
            type = "feat"
        } else if deleted > 0 && added == 0 && modified == 0 {
            type = "chore"
        } else if paths.allSatisfy({ $0.hasSuffix("Test.swift") || $0.hasSuffix("Tests.swift") || $0.contains("test") }) {
            type = "test"
        } else if paths.allSatisfy({ $0.hasSuffix(".md") || $0.hasSuffix(".txt") }) {
            type = "docs"
        } else {
            type = modified > added ? "fix" : "feat"
        }

        let description: String
        let fileCount = lines.count
        if fileCount == 1 {
            let fileName = URL(fileURLWithPath: paths[0]).deletingPathExtension().lastPathComponent
            description = added > 0 ? "add \(fileName)" : "update \(fileName)"
        } else {
            description = "\(type == "feat" ? "add" : "update") \(fileCount) files"
        }

        return "\(type)\(scope): \(description)"
    }
}
