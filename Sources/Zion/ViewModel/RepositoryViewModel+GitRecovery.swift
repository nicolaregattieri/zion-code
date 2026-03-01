import Foundation
import SwiftUI

extension RepositoryViewModel {

    // MARK: - Recovery Snapshots

    func refreshRecoverySnapshots(includeDangling: Bool = true) {
        guard let repositoryURL else {
            recoverySnapshots = []
            recoverySnapshotsStatus = ""
            return
        }

        recoverySnapshotsTask?.cancel()
        isRecoverySnapshotsLoading = true
        recoverySnapshotsTask = Task {
            do {
                let active = try await loadActiveRecoverySnapshots(in: repositoryURL)
                let dangling = includeDangling ? (try await loadDanglingRecoverySnapshots(in: repositoryURL)) : []

                var byHash: [String: RecoverySnapshot] = [:]
                for item in active { byHash[item.hash] = item }
                for item in dangling where byHash[item.hash] == nil { byHash[item.hash] = item }

                let merged = byHash.values.sorted { $0.date > $1.date }
                recoverySnapshots = merged
                recoverySnapshotsRepositoryPath = repositoryURL.path
                recoverySnapshotsStatus = merged.isEmpty
                    ? L10n("recovery.status.empty")
                    : L10n("recovery.status.loaded", "\(merged.count)")
                isRecoverySnapshotsLoading = false
            } catch is CancellationError {
                return
            } catch {
                isRecoverySnapshotsLoading = false
                recoverySnapshotsStatus = L10n("recovery.status.failed")
                logger.log(.warn, "Recovery snapshot scan failed: \(error.localizedDescription)", source: #function)
            }
        }
    }

    func copyRecoverySnapshotReference(_ snapshot: RecoverySnapshot) {
        let value = snapshot.reference ?? snapshot.hash
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        statusMessage = L10n("recovery.copy.success", value)
    }

    func restoreRecoverySnapshot(_ snapshot: RecoverySnapshot) {
        if let reference = snapshot.reference, !reference.clean.isEmpty {
            selectedStash = reference
            applySelectedStash()
            return
        }
        runGitAction(label: "Restore snapshot", args: ["checkout", snapshot.hash, "--", "."])
    }

    func loadActiveRecoverySnapshots(in repositoryURL: URL) async throws -> [RecoverySnapshot] {
        let output = try await worker.runAction(
            args: ["stash", "list", "--format=%gD%x1F%H%x1F%ct%x1F%gs"],
            in: repositoryURL
        )

        return output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let fields = line.split(separator: Constants.gitFieldSeparator, omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 4 else { return nil }
            let ref = fields[0].clean
            let hash = fields[1].clean
            let timestamp = TimeInterval(fields[2].clean) ?? 0
            let subject = fields[3].clean
            guard !ref.isEmpty, !hash.isEmpty else { return nil }
            return RecoverySnapshot(
                hash: hash,
                shortHash: String(hash.prefix(8)),
                reference: ref,
                subject: subject,
                date: Date(timeIntervalSince1970: timestamp),
                source: .activeStash
            )
        }
    }

    func loadDanglingRecoverySnapshots(in repositoryURL: URL) async throws -> [RecoverySnapshot] {
        let fsck = try await worker.runActionAllowingFailure(
            args: ["fsck", "--no-reflogs", "--full", "--unreachable", "--no-progress"],
            in: repositoryURL
        )
        let hashes = fsck.output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> String? in
                let text = String(line)
                guard text.hasPrefix("unreachable commit ") else { return nil }
                return String(text.dropFirst("unreachable commit ".count)).clean
            }
            .filter { !$0.isEmpty }

        guard !hashes.isEmpty else { return [] }
        let limited = Array(hashes.prefix(Constants.Limits.maxDanglingSnapshots))
        let showOutput = try await worker.runAction(
            args: ["show", "-s", "--format=%H%x1F%h%x1F%ct%x1F%s"] + limited,
            in: repositoryURL
        )

        return showOutput.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let fields = line.split(separator: Constants.gitFieldSeparator, omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 4 else { return nil }
            let hash = fields[0].clean
            let shortHash = fields[1].clean
            let timestamp = TimeInterval(fields[2].clean) ?? 0
            let subject = fields[3].clean
            guard subject.contains("zion-safety-") || subject.contains("zion-transfer-") else { return nil }
            return RecoverySnapshot(
                hash: hash,
                shortHash: shortHash.isEmpty ? String(hash.prefix(8)) : shortHash,
                reference: nil,
                subject: subject,
                date: Date(timeIntervalSince1970: timestamp),
                source: .danglingSnapshot
            )
        }
    }

    func runStashRestoreAction(reference: String, shouldPop: Bool) {
        guard let repositoryURL else {
            lastError = GitClientError.repositoryNotSelected.localizedDescription
            return
        }

        actionTask?.cancel()
        isBusy = true
        let verb = shouldPop ? "pop" : "apply"

        actionTask = Task {
            do {
                let _ = try await worker.runAction(args: ["stash", verb, reference], in: repositoryURL)
                try Task.checkCancellation()
                clearError()
                statusMessage = shouldPop ? L10n("stash.pop.success") : L10n("stash.apply.success")
                refreshRepository(setBusy: true)
            } catch is CancellationError {
                return
            } catch {
                isBusy = false
                if handleStashRestoreFailure(error, reference: reference, pop: shouldPop) {
                    return
                }
                if let friendly = friendlyStashRestoreErrorMessage(error, reference: reference, pop: shouldPop) {
                    clearError()
                    lastError = friendly
                    statusMessage = friendly
                    logger.log(.error, friendly, source: #function)
                    return
                }
                handleError(error)
            }
        }
    }

    @discardableResult
    func handleStashRestoreFailure(_ error: Error, reference: String, pop: Bool) -> Bool {
        let raw = error.localizedDescription.lowercased()
        let overwriteBlocked = raw.contains("would be overwritten by merge")
            || raw.contains("please commit your changes or stash them before you merge")

        guard overwriteBlocked else { return false }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n("stash.restore.blocked.title")
        alert.informativeText = L10n("stash.restore.blocked.message", reference)
        alert.addButton(withTitle: L10n("stash.restore.blocked.autoStashRetry"))
        alert.addButton(withTitle: L10n("Cancelar"))

        if alert.runModal() == .alertFirstButtonReturn {
            runAutoStashAndRetry(reference: reference, pop: pop)
        } else {
            clearError()
            statusMessage = L10n("stash.restore.blocked.cancelled")
        }
        return true
    }

    func runAutoStashAndRetry(reference: String, pop: Bool) {
        guard let repositoryURL else {
            lastError = GitClientError.repositoryNotSelected.localizedDescription
            return
        }

        actionTask?.cancel()
        isBusy = true
        let safetyMessage = "zion-safety-\(UUID().uuidString.prefix(8))"
        let verb = pop ? "pop" : "apply"

        actionTask = Task {
            do {
                let isTransferFlow = await isTransferStash(reference: reference, in: repositoryURL)
                let stableReference = await stableStashReferenceForRetry(reference, in: repositoryURL)
                let _ = try await worker.runAction(
                    args: ["stash", "push", "--include-untracked", "-m", safetyMessage],
                    in: repositoryURL
                )
                let safetyRef = try? await latestStashReference(in: repositoryURL)
                let _ = try await worker.runAction(args: ["stash", verb, stableReference], in: repositoryURL)

                if isTransferFlow, let safetyRef, !safetyRef.clean.isEmpty {
                    do {
                        let _ = try await worker.runAction(args: ["stash", "apply", safetyRef], in: repositoryURL)
                        statusMessage = L10n("stash.restore.blocked.transferRestored", safetyMessage)
                    } catch {
                        let files = (try? await worker.listConflictedFiles(in: repositoryURL)) ?? []
                        if let first = files.first {
                            conflictedFiles = files
                            isConflictViewVisible = true
                            selectConflictFile(first.path)
                            statusMessage = L10n("stash.restore.blocked.transferConflicts")
                        } else {
                            statusMessage = L10n("stash.restore.blocked.transferPartial", safetyMessage)
                        }
                    }
                } else {
                    statusMessage = L10n("stash.restore.blocked.retried", safetyMessage)
                }

                try Task.checkCancellation()
                clearError()
                refreshRepository(setBusy: true)
            } catch is CancellationError {
                return
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    func isTransferStash(reference: String, in repositoryURL: URL) async -> Bool {
        let normalized = reference.clean
        guard !normalized.isEmpty else { return false }
        let resolved = (await resolveStashReference(normalized)) ?? normalized

        let output = (try? await worker.runAction(args: ["stash", "list", "--format=%H%x09%gD%x09%s"], in: repositoryURL)) ?? ""
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            let hash = String(parts[0])
            let ref = String(parts[1])
            let subject = String(parts[2])
            guard subject.contains("zion-transfer-") else { continue }

            if normalized == ref || normalized == hash || hash.hasPrefix(normalized) || resolved == ref || resolved == hash {
                return true
            }
        }
        return false
    }

    func stableStashReferenceForRetry(_ reference: String, in repositoryURL: URL) async -> String {
        let cleaned = reference.clean
        let isOrdinal = cleaned.range(of: "^stash@\\{\\d+\\}$", options: .regularExpression) != nil
        guard isOrdinal else { return cleaned }

        let hash = (try? await worker.runAction(args: ["rev-parse", cleaned], in: repositoryURL).clean) ?? ""
        return hash.isEmpty ? cleaned : hash
    }

    func friendlyStashRestoreErrorMessage(_ error: Error, reference: String, pop: Bool) -> String? {
        guard case let GitClientError.commandFailed(_, message) = error else {
            return nil
        }

        let normalized = message.lowercased()
        if normalized.contains("no stash entries found") || normalized.contains("stash not found") {
            return L10n("stash.restore.error.noEntries")
        }
        if normalized.contains("not a valid reference")
            || normalized.contains("unknown revision")
            || normalized.contains("bad revision") {
            return L10n("stash.restore.error.invalidReference", reference)
        }
        if normalized.contains("conflict")
            || normalized.contains("merge conflict")
            || normalized.contains("could not apply") {
            return pop
                ? L10n("stash.restore.error.popConflict")
                : L10n("stash.restore.error.applyConflict")
        }

        return pop
            ? L10n("stash.restore.error.popGeneric")
            : L10n("stash.restore.error.applyGeneric")
    }

    // MARK: - Stash Reference Resolution

    func resolveStashReference(_ input: String) async -> String? {
        let value = input.clean
        guard !value.isEmpty else { return nil }

        // 1. If it's already a stash@{n} format, try to extract just that part
        if value.hasPrefix("stash@{") || value.contains("stash@{") {
            if let range = value.range(of: "stash@{[0-9]+}", options: .regularExpression) {
                return String(value[range])
            }
        }

        // 2. If it's a hash, we need to find which stash@{n} corresponds to it
        let isHex = value.range(of: "^[0-9a-fA-F]{7,40}$", options: .regularExpression) != nil
        if isHex {
            guard let url = repositoryURL else { return value }
            // Run git stash list with hashes to find the match
            do {
                let output = try await worker.runAction(args: ["stash", "list", "--format=%H %gD"], in: url)
                for line in output.split(separator: "\n") {
                    let parts = line.split(separator: " ")
                    if parts.count >= 2 {
                        let hash = String(parts[0])
                        let stashRef = String(parts[1])
                        if hash.hasPrefix(value) || value.hasPrefix(hash) {
                            return stashRef // Found stash@{n}
                        }
                    }
                }
            } catch {
                logger.log(.warn, "Failed to resolve stash ref: \(error.localizedDescription)", context: value, source: #function)
                return value // Fallback to hash if it fails
            }
        }

        return value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? value
    }
}
