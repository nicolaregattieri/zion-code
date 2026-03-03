import Foundation

// MARK: - Bisect Enums

enum BisectPhase: Equatable {
    case inactive
    case awaitingGoodCommit(badCommitHash: String)
    case active(currentHash: String, stepsRemaining: Int)
    case foundCulprit(commitHash: String)
}

enum BisectCommitRole {
    case none
    case currentTest
    case markedGood
    case markedBad
    case culprit
    case outsideRange
}

enum BisectResult {
    case continuing(nextHash: String, stepsRemaining: Int)
    case foundCulprit(commitHash: String)
}

// MARK: - Bisect Actions

extension RepositoryViewModel {

    private static func isValidCommitHash(_ hash: String) -> Bool {
        hash.count >= 7 && hash.count <= 40 && hash.allSatisfy { $0.isHexDigit }
    }

    func startBisect(badCommitHash: String) {
        guard Self.isValidCommitHash(badCommitHash) else {
            lastError = L10n("bisect.error.invalidHash")
            return
        }
        guard let url = repositoryURL else { return }

        bisectTask?.cancel()
        bisectTask = Task {
            do {
                let _ = try await worker.runActionAllowingFailure(
                    args: ["bisect", "start"],
                    in: url
                )
                let _ = try await worker.runActionAllowingFailure(
                    args: ["bisect", "bad", badCommitHash],
                    in: url
                )

                bisectBadCommits.insert(badCommitHash)
                bisectPhase = .awaitingGoodCommit(badCommitHash: badCommitHash)
                statusMessage = L10n("bisect.status.pickGood")
                logger.log(.git, "Bisect started", context: "bad=\(badCommitHash.prefix(8))")
            } catch {
                lastError = error.localizedDescription
                clearBisectState()
            }
        }
    }

    func markCommitGood(_ commitHash: String) {
        guard Self.isValidCommitHash(commitHash) else {
            lastError = L10n("bisect.error.invalidHash")
            return
        }
        guard let url = repositoryURL else { return }

        bisectTask?.cancel()
        bisectTask = Task {
            do {
                let (output, _) = try await worker.runActionAllowingFailure(
                    args: ["bisect", "good", commitHash],
                    in: url
                )

                bisectGoodCommits.insert(commitHash)
                handleBisectResult(parseBisectOutput(output))
                refreshRepository(setBusy: false)
                logger.log(.git, "Bisect good", context: "hash=\(commitHash.prefix(8)), output=\(output.prefix(120))")
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func bisectMarkGood() {
        guard let url = repositoryURL else { return }

        bisectTask?.cancel()
        bisectTask = Task {
            do {
                let (output, _) = try await worker.runActionAllowingFailure(
                    args: ["bisect", "good"],
                    in: url
                )

                bisectGoodCommits.insert(bisectCurrentHash)
                handleBisectResult(parseBisectOutput(output))
                refreshRepository(setBusy: false)
                logger.log(.git, "Bisect mark good", context: output.prefix(120).description)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func bisectMarkBad() {
        guard let url = repositoryURL else { return }

        bisectTask?.cancel()
        bisectTask = Task {
            do {
                let (output, _) = try await worker.runActionAllowingFailure(
                    args: ["bisect", "bad"],
                    in: url
                )

                bisectBadCommits.insert(bisectCurrentHash)
                handleBisectResult(parseBisectOutput(output))
                refreshRepository(setBusy: false)
                logger.log(.git, "Bisect mark bad", context: output.prefix(120).description)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func bisectSkip() {
        guard let url = repositoryURL else { return }

        bisectTask?.cancel()
        bisectTask = Task {
            do {
                let (output, _) = try await worker.runActionAllowingFailure(
                    args: ["bisect", "skip"],
                    in: url
                )

                handleBisectResult(parseBisectOutput(output))
                refreshRepository(setBusy: false)
                logger.log(.git, "Bisect skip", context: output.prefix(120).description)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func bisectAbort() {
        guard let url = repositoryURL else { return }

        bisectTask?.cancel()
        bisectTask = Task {
            let _ = try? await worker.runActionAllowingFailure(
                args: ["bisect", "reset"],
                in: url
            )
            clearBisectState()
            statusMessage = L10n("bisect.status.aborted")
            refreshRepository(setBusy: true)
            logger.log(.git, "Bisect aborted")
        }
    }

    func bisectFinish() {
        guard let url = repositoryURL else { return }

        bisectTask?.cancel()
        bisectTask = Task {
            let _ = try? await worker.runActionAllowingFailure(
                args: ["bisect", "reset"],
                in: url
            )
            clearBisectState()
            statusMessage = L10n("bisect.status.done")
            refreshRepository(setBusy: true)
            logger.log(.git, "Bisect finished")
        }
    }

    // MARK: - Result Handling

    private func handleBisectResult(_ result: BisectResult) {
        switch result {
        case .continuing(let nextHash, let steps):
            bisectPhase = .active(currentHash: nextHash, stepsRemaining: steps)
            bisectCurrentHash = nextHash
            statusMessage = L10n("bisect.status.testing", String(nextHash.prefix(8)))
        case .foundCulprit(let culpritHash):
            bisectPhase = .foundCulprit(commitHash: culpritHash)
            bisectBadCommits.insert(culpritHash)
            bisectCurrentHash = culpritHash
            statusMessage = L10n("bisect.status.found", String(culpritHash.prefix(8)))
            bisectExplainCulprit(commitHash: culpritHash)
        }
    }

    // MARK: - AI Explanation

    func bisectExplainCulprit(commitHash: String) {
        guard let url = repositoryURL, isAIConfigured else { return }
        guard Self.isValidCommitHash(commitHash) else { return }

        isBisectAILoading = true
        bisectAIExplanation = ""

        bisectTask = Task {
            do {
                let diff = try await worker.runAction(
                    args: ["show", "--format=", "-p", commitHash],
                    in: url
                )
                let diffStat = try await worker.runAction(
                    args: ["show", "--format=", "--stat", commitHash],
                    in: url
                )

                let explanation = try await aiClient.explainBisectCulprit(
                    commitHash: commitHash,
                    diff: diff,
                    diffStat: diffStat,
                    provider: aiProvider,
                    apiKey: aiAPIKey
                )

                // Guard against stale result if bisect was aborted during AI call
                guard !Task.isCancelled, bisectPhase != .inactive else { return }
                bisectAIExplanation = explanation
                isBisectAILoading = false
                logger.log(.ai, "Bisect AI explanation generated", context: "hash=\(commitHash.prefix(8))")
            } catch {
                guard !Task.isCancelled, bisectPhase != .inactive else { return }
                isBisectAILoading = false
                bisectAIExplanation = L10n("bisect.ai.error")
                logger.log(.ai, "Bisect AI explanation failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Output Parsing

    func parseBisectOutput(_ output: String) -> BisectResult {
        let safeOutput = String(output.prefix(10_000))

        // Pattern: "<hash> is the first bad commit"
        if safeOutput.contains("is the first bad commit") {
            let lines = safeOutput.components(separatedBy: "\n")
            for line in lines {
                if line.contains("is the first bad commit") {
                    let hash = String(line.split(separator: " ").first ?? "")
                    if Self.isValidCommitHash(hash) {
                        return .foundCulprit(commitHash: hash)
                    }
                }
            }
        }

        // Pattern: "Bisecting: N revisions left to test after this (roughly M steps)"
        // followed by "[<hash>] <subject>"
        var stepsRemaining = 0
        var nextHash = ""

        let lines = safeOutput.components(separatedBy: "\n")
        for line in lines {
            if line.contains("roughly") && line.contains("step") {
                let parts = line.components(separatedBy: "roughly ")
                if parts.count > 1 {
                    let afterRoughly = parts[1]
                    let stepStr = afterRoughly.components(separatedBy: " ").first ?? "0"
                    stepsRemaining = Int(stepStr) ?? 0
                }
            }
            // "[abc1234...] commit subject"
            if line.hasPrefix("[") {
                let trimmed = line.dropFirst()
                if let closeBracket = trimmed.firstIndex(of: "]") {
                    let candidate = String(trimmed[trimmed.startIndex..<closeBracket])
                    if Self.isValidCommitHash(candidate) {
                        nextHash = candidate
                    }
                }
            }
        }

        if !nextHash.isEmpty {
            return .continuing(nextHash: nextHash, stepsRemaining: stepsRemaining)
        }

        return .continuing(nextHash: bisectCurrentHash, stepsRemaining: stepsRemaining)
    }

    // MARK: - State Management

    func clearBisectState() {
        bisectPhase = .inactive
        bisectGoodCommits.removeAll()
        bisectBadCommits.removeAll()
        bisectCurrentHash = ""
        bisectAIExplanation = ""
        isBisectAILoading = false
        bisectTask?.cancel()
        bisectTask = nil
    }

    func bisectRole(for commitHash: String) -> BisectCommitRole {
        switch bisectPhase {
        case .inactive:
            return .none
        case .awaitingGoodCommit:
            if bisectBadCommits.contains(commitHash) { return .markedBad }
            return .none
        case .active:
            if commitHash == bisectCurrentHash { return .currentTest }
            if bisectGoodCommits.contains(commitHash) { return .markedGood }
            if bisectBadCommits.contains(commitHash) { return .markedBad }
            return .none
        case .foundCulprit(let culpritHash):
            if commitHash == culpritHash { return .culprit }
            if bisectGoodCommits.contains(commitHash) { return .markedGood }
            if bisectBadCommits.contains(commitHash) { return .markedBad }
            return .none
        }
    }
}
