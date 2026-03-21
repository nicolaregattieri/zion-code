import Foundation
import SwiftUI

extension RepositoryViewModel {

    // MARK: - Discard All Changes

    func discardAllChanges() {
        guard let repositoryURL else { return }
        discardAllChanges(in: repositoryURL, successMessage: L10n("discardAll.success.current"))
    }

    func discardAllChanges(inWorktree worktree: WorktreeItem) {
        let targetURL = URL(fileURLWithPath: worktree.path)
        let displayName = worktreeDisplayName(worktree)
        discardAllChanges(in: targetURL, successMessage: L10n("discardAll.success.worktree", displayName))
    }

    func discardAllChanges(in targetURL: URL, successMessage: String) {
        actionTask?.cancel()
        isBusy = true
        actionTask = Task {
            do {
                await abortInProgressIntegrationIfAny(in: targetURL)
                try await createDiscardSnapshotIfPossible(in: targetURL, tag: "zion-pre-discard-all")

                // Ensure tree is fully clean (stash push already cleans, but reset + clean
                // handle edge cases like staged-only changes or ignored-but-tracked files)
                let _ = try await worker.runAction(args: ["reset", "--hard", "HEAD"], in: targetURL)
                let _ = try await worker.runAction(args: ["clean", "-fd"], in: targetURL)
                try Task.checkCancellation()
                clearError()
                statusMessage = successMessage
                refreshRepository(setBusy: true)
            } catch is CancellationError {
                isBusy = false
                return
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    // MARK: - Pending Transfer

    func transferPendingChanges(toWorktree worktree: WorktreeItem, keepInCurrentWorktree: Bool) {
        guard let repositoryURL else {
            lastError = GitClientError.repositoryNotSelected.localizedDescription
            return
        }

        let sourceURL = repositoryURL
        let targetURL = URL(fileURLWithPath: worktree.path)
        let marker = "zion-transfer-\(UUID().uuidString)"

        actionTask?.cancel()
        isBusy = true
        actionTask = Task {
            var stashRef: String?
            var sourceWasStashed = false
            var sourceRecoverySucceeded = false

            do {
                let status = try await worker.runAction(args: ["status", "--porcelain"], in: sourceURL)
                if status.clean.isEmpty {
                    clearError()
                    statusMessage = L10n("pending.transfer.noChanges")
                    isBusy = false
                    return
                }

                let _ = try await worker.runAction(
                    args: ["stash", "push", "--include-untracked", "-m", marker],
                    in: sourceURL
                )
                sourceWasStashed = true

                stashRef = try await transferStashReference(marker: marker, in: sourceURL)
                guard let stashRef else {
                    throw GitClientError.commandFailed(
                        command: "stash list",
                        message: L10n("pending.transfer.error.ref")
                    )
                }

                if keepInCurrentWorktree {
                    let _ = try await worker.runAction(args: ["stash", "apply", stashRef], in: sourceURL)
                    sourceWasStashed = false
                }

                let _ = try await worker.runAction(args: ["stash", "apply", stashRef], in: targetURL)
                let _ = try await worker.runAction(args: ["stash", "drop", stashRef], in: sourceURL)

                try Task.checkCancellation()
                clearError()
                let worktreeName = worktreeDisplayName(worktree)
                statusMessage = keepInCurrentWorktree
                    ? L10n("pending.transfer.copy.success", worktreeName)
                    : L10n("pending.transfer.move.success", worktreeName)
                refreshRepository(setBusy: true)
            } catch is CancellationError {
                isBusy = false
                return
            } catch {
                if sourceWasStashed, let stashRef {
                    if (try? await worker.runAction(args: ["stash", "apply", stashRef], in: sourceURL)) != nil {
                        sourceRecoverySucceeded = true
                    }
                }
                presentPendingTransferSupportAlert(
                    targetWorktree: worktree,
                    modeLabel: keepInCurrentWorktree ? L10n("pending.transfer.copy.short") : L10n("pending.transfer.move.short"),
                    stashReference: stashRef,
                    sourceRecovered: sourceRecoverySucceeded,
                    sourceWasStashed: sourceWasStashed,
                    errorDescription: error.localizedDescription
                )
                clearError()
                statusMessage = L10n("pending.transfer.support.handled")
                isBusy = false
                logger.log(.warn, "Pending transfer requires manual resolution: \(error.localizedDescription)", source: #function)
                refreshRepository(setBusy: false)
            }
        }
    }

    func transferStashReference(marker: String, in repositoryURL: URL) async throws -> String? {
        let output = try await worker.runAction(args: ["stash", "list", "--format=%gD%x09%s"], in: repositoryURL)
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let ref = String(parts[0])
            let subject = String(parts[1])
            if subject == marker {
                return ref
            }
        }
        return nil
    }

    func presentPendingTransferSupportAlert(
        targetWorktree: WorktreeItem,
        modeLabel: String,
        stashReference: String?,
        sourceRecovered: Bool,
        sourceWasStashed: Bool,
        errorDescription: String
    ) {
        let targetName = worktreeDisplayName(targetWorktree)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n("pending.transfer.support.title")

        var details: [String] = [
            L10n("pending.transfer.support.message", modeLabel, targetName),
            L10n("pending.transfer.support.error", errorDescription)
        ]

        if sourceWasStashed {
            if sourceRecovered {
                details.append(L10n("pending.transfer.support.sourceRecovered"))
            } else {
                details.append(L10n("pending.transfer.support.sourceNotRecovered"))
            }
        }

        if let stashReference, !stashReference.clean.isEmpty {
            details.append(L10n("pending.transfer.support.stash", stashReference))
            details.append(L10n("pending.transfer.support.keepStash"))
        }

        if aiTransferSupportHintsEnabled {
            details.append(
                isAIConfigured
                    ? L10n("pending.transfer.support.ai.available")
                    : L10n("pending.transfer.support.ai.optional")
            )
        }

        alert.informativeText = details.joined(separator: "\n\n")
        var actions: [() -> Void] = []

        alert.addButton(withTitle: L10n("pending.transfer.support.openTarget"))
        actions.append {
            self.openTransferSupportTarget(targetWorktree, stashReference: stashReference, shouldOpenConflictResolver: false)
        }

        let canUseAIAction = aiTransferSupportHintsEnabled && isAIConfigured
        if canUseAIAction {
            alert.addButton(withTitle: L10n("pending.transfer.support.openTargetAI"))
            actions.append {
                self.openTransferSupportTarget(targetWorktree, stashReference: stashReference, shouldOpenConflictResolver: true)
            }
        }

        if let stashReference, !stashReference.clean.isEmpty {
            alert.addButton(withTitle: L10n("pending.transfer.support.copyStash"))
            actions.append {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(stashReference, forType: .string)
                self.statusMessage = L10n("pending.transfer.support.copied")
            }
        }

        alert.addButton(withTitle: L10n("OK"))
        actions.append {}

        let response = alert.runModal()
        let index = Int(response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue)
        guard index >= 0 && index < actions.count else { return }
        actions[index]()
    }

    func openTransferSupportTarget(
        _ targetWorktree: WorktreeItem,
        stashReference: String?,
        shouldOpenConflictResolver: Bool
    ) {
        openWorktreeInZion(targetWorktree, navigateToCode: false, sectionAfterOpen: .operations)
        guard shouldOpenConflictResolver else { return }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Constants.Timing.transferSupportDelay)
            guard let repositoryURL else { return }

            var sourceStashApplyError: String?
            var safetyStashApplyError: String?
            var safetyRef: String?
            if let stashReference, !stashReference.clean.isEmpty {
                let safety = "zion-ai-support-\(UUID().uuidString.prefix(8))"
                _ = try? await worker.runAction(
                    args: ["stash", "push", "--include-untracked", "-m", safety],
                    in: repositoryURL
                )
                safetyRef = try? await latestStashReference(in: repositoryURL)

                // 1) Apply incoming/source stash.
                do {
                    let _ = try await worker.runAction(args: ["stash", "apply", stashReference], in: repositoryURL)
                } catch {
                    sourceStashApplyError = error.localizedDescription
                }

                // 2) Re-apply local/safety stash to preserve local work and surface real conflicts.
                if sourceStashApplyError == nil, let safetyRef {
                    do {
                        let _ = try await worker.runAction(args: ["stash", "apply", safetyRef], in: repositoryURL)
                    } catch {
                        safetyStashApplyError = error.localizedDescription
                    }
                }
            }

            do {
                let files = try await worker.listConflictedFiles(in: repositoryURL)
                conflictedFiles = files
                if let first = files.first(where: { !$0.isResolved }) {
                    selectConflictFile(first.path)
                } else {
                    selectedConflictFile = nil
                    conflictBlocks = []
                }

                if files.isEmpty {
                    isConflictViewVisible = false
                    let blockedByLocalChanges =
                        Self.isStashApplyBlockedByLocalChanges(sourceStashApplyError)
                        || Self.isStashApplyBlockedByLocalChanges(safetyStashApplyError)

                    // NOTE (release follow-up): when two worktrees edit the same file/line, Git can block stash apply
                    // without producing unmerged (-U) entries. In that case we do not get conflict files and must
                    // guide users through local-overwrite recovery. Revisit this flow with a deterministic same-file resolver.

                    if blockedByLocalChanges {
                        presentTransferLocalCollisionAlert(
                            targetWorktree: targetWorktree,
                            incomingStashRef: stashReference,
                            safetyStashRef: safetyRef,
                            sourceError: sourceStashApplyError,
                            safetyError: safetyStashApplyError
                        )
                        statusMessage = L10n("pending.transfer.support.localCollision.status")
                    } else if sourceStashApplyError != nil || safetyStashApplyError != nil {
                        statusMessage = L10n("pending.transfer.support.ai.result.failed")
                    } else {
                        statusMessage = L10n("pending.transfer.support.ai.result.clean")
                    }
                } else {
                    isConflictViewVisible = true
                    statusMessage = L10n("pending.transfer.support.ai.result.conflicts")
                }
                refreshRepository(setBusy: false)
            } catch {
                isConflictViewVisible = false
                handleError(error)
            }
        }
    }

    func presentTransferLocalCollisionAlert(
        targetWorktree: WorktreeItem,
        incomingStashRef: String?,
        safetyStashRef: String?,
        sourceError: String?,
        safetyError: String?
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n("pending.transfer.support.localCollision.title")

        var details: [String] = [
            L10n("pending.transfer.support.localCollision.message", worktreeDisplayName(targetWorktree))
        ]
        if let sourceError, !sourceError.clean.isEmpty {
            details.append(L10n("pending.transfer.support.localCollision.incomingError", sourceError))
        }
        if let safetyError, !safetyError.clean.isEmpty {
            details.append(L10n("pending.transfer.support.localCollision.localError", safetyError))
        }
        if let safetyStashRef, !safetyStashRef.clean.isEmpty {
            details.append(L10n("pending.transfer.support.localCollision.safetyRef", safetyStashRef))
        }
        if let incomingStashRef, !incomingStashRef.clean.isEmpty {
            details.append(L10n("pending.transfer.support.localCollision.incomingRef", incomingStashRef))
        }
        alert.informativeText = details.joined(separator: "\n\n")

        alert.addButton(withTitle: L10n("pending.transfer.support.localCollision.openOps"))
        if let safetyStashRef, !safetyStashRef.clean.isEmpty {
            alert.addButton(withTitle: L10n("pending.transfer.support.localCollision.copySafety"))
            alert.addButton(withTitle: L10n("OK"))
            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(safetyStashRef, forType: .string)
                statusMessage = L10n("pending.transfer.support.localCollision.copiedSafety")
            }
            return
        }
        _ = alert.runModal()
    }

    static func isStashApplyBlockedByLocalChanges(_ description: String?) -> Bool {
        guard let description else { return false }
        let normalized = description.lowercased()
        return normalized.contains("would be overwritten by merge")
            || normalized.contains("please commit your changes or stash them before you merge")
            || normalized.contains("local changes")
    }

    static func isDiscardSnapshotRecoverableFailure(_ description: String?) -> Bool {
        guard let description, !description.clean.isEmpty else { return false }
        let normalized = description.lowercased()
        return normalized.contains("needs merge")
            || normalized.contains("cannot save the current index state")
            || normalized.contains("could not write index")
            || normalized.contains("unable to write index")
    }

    func abortInProgressIntegrationIfAny(in targetURL: URL) async {
        let abortCommands = [
            ["merge", "--abort"],
            ["rebase", "--abort"],
            ["cherry-pick", "--abort"],
        ]

        for args in abortCommands {
            if let result = try? await worker.runActionAllowingFailure(args: args, in: targetURL),
               result.status == 0 {
                logger.log(.info, "Aborted in-progress operation: \(args.joined(separator: " "))", source: #function)
            }
        }
    }

    func createDiscardSnapshotIfPossible(in targetURL: URL, tag: String) async throws {
        // Snapshot with --include-untracked since clean -fd deletes untracked files.
        // If snapshot fails due unmerged index (common after stash pop conflicts),
        // continue with explicit discard because the user requested destructive cleanup.
        let status = try await worker.runAction(args: ["status", "--porcelain"], in: targetURL)
        guard !status.clean.isEmpty else { return }

        do {
            let _ = try await worker.runAction(
                args: ["stash", "push", "--include-untracked", "-m", tag],
                in: targetURL
            )
            logger.log(.info, "Pre-snapshot created: \(tag)", source: #function)
        } catch {
            let message = error.localizedDescription
            if Self.isDiscardSnapshotRecoverableFailure(message) {
                logger.log(
                    .warn,
                    "Pre-snapshot skipped due recoverable index state: \(message)",
                    context: tag,
                    source: #function
                )
                return
            }
            throw error
        }
    }

    func latestStashReference(in repositoryURL: URL) async throws -> String? {
        let output = try await worker.runAction(args: ["stash", "list", "-1", "--format=%gD"], in: repositoryURL)
        let ref = output.clean
        return ref.isEmpty ? nil : ref
    }
}
