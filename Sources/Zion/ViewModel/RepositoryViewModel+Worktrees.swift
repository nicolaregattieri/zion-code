import Foundation
import SwiftUI

extension RepositoryViewModel {

    // MARK: - Worktrees

    /// Lightweight worktree-only refresh. Skips the full repo reload so the
    /// sidebar worktree card and the Worktrees panel can update reactively
    /// (e.g. when the user removed worktrees from a terminal, or another
    /// Zion session pruned them) without dragging in the cold-cache commit
    /// reload. Safe to call on `.onAppear` — bails when no repo is open.
    func refreshWorktreesOnly() {
        guard let repositoryURL else { return }
        let worker = self.worker
        Task { [weak self] in
            guard let self else { return }
            let resolved = (try? await worker.worktreeList(in: repositoryURL, includeStatus: false)) ?? []
            await MainActor.run {
                let merged = self.mergeWorktreeStatusIfNeeded(resolved, includeWorktreeStatus: false)
                if self.worktrees != merged { self.worktrees = merged }
            }
        }
    }

    func addWorktree() {
        let path = worktreePathInput.clean
        guard !path.isEmpty else { return }

        let branch = worktreeBranchInput.clean
        addWorktree(path: path, branch: branch.isEmpty ? nil : branch)
    }

    func addWorktree(path: String, branch: String?) {
        let cleanedPath = path.clean
        guard !cleanedPath.isEmpty else { return }

        var args = ["worktree", "add", cleanedPath]
        if let branch, !branch.clean.isEmpty {
            args.append(branch.clean)
        }
        runGitAction(label: "Adicionar worktree", args: args)
    }

    func smartCreateWorktree() {
        guard let repositoryURL else { return }

        let manualPath = worktreePathInput.clean
        let manualBranch = worktreeBranchInput.clean
        let slug = worktreeNameSlug

        let resolvedBranch = manualBranch.isEmpty ? "\(worktreePrefix.rawValue)/\(slug)" : manualBranch
        let resolvedPath: String = {
            if !manualPath.isEmpty {
                return manualPath
            }
            guard !slug.isEmpty else { return "" }
            let parentDir = repositoryURL.deletingLastPathComponent()
            let repoName = repositoryURL.lastPathComponent
            let baseName = "\(repoName)-\(worktreePrefix.rawValue)-\(slug)"
            return uniquePath(forBaseName: baseName, in: parentDir).path
        }()

        guard !resolvedPath.isEmpty, !resolvedBranch.clean.isEmpty else {
            statusMessage = L10n("worktree.smart.missing")
            return
        }

        let cleanedBranch = resolvedBranch.clean
        let branchDecision: (branch: String, reuseExisting: Bool)
        if localBranchExists(named: cleanedBranch) {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = L10n("worktree.smart.branchExists.title")
            alert.informativeText = L10n("worktree.smart.branchExists.message", cleanedBranch)
            alert.addButton(withTitle: L10n("worktree.smart.branchExists.reuse"))
            alert.addButton(withTitle: L10n("worktree.smart.branchExists.createSuffix"))
            alert.addButton(withTitle: L10n("Cancelar"))

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                branchDecision = (cleanedBranch, true)
            } else if response == .alertSecondButtonReturn {
                branchDecision = (uniqueBranchNameForWorktree(from: cleanedBranch), false)
            } else {
                statusMessage = L10n("worktree.smart.branchExists.cancelled")
                return
            }
        } else {
            branchDecision = (cleanedBranch, false)
        }

        actionTask?.cancel()
        isBusy = true
        actionTask = Task {
            do {
                let addArgs: [String]
                if branchDecision.reuseExisting {
                    addArgs = ["worktree", "add", resolvedPath, branchDecision.branch]
                } else {
                    addArgs = ["worktree", "add", "-b", branchDecision.branch, resolvedPath]
                }

                let _ = try await worker.runAction(
                    args: addArgs,
                    in: repositoryURL
                )
                try Task.checkCancellation()
                clearError()
                statusMessage = L10n("worktree.smart.created", branchDecision.branch)

                worktreeNameInput = ""
                worktreePathInput = ""
                worktreeBranchInput = ""
                isWorktreeAdvancedExpanded = false

                let created = WorktreeItem(
                    path: resolvedPath,
                    head: "",
                    branch: branchDecision.branch,
                    isMainWorktree: false,
                    isDetached: false,
                    isLocked: false,
                    lockReason: "",
                    isPrunable: false,
                    pruneReason: "",
                    isCurrent: false
                )
                openWorktreeInZion(created)
            } catch is CancellationError {
                isBusy = false
                return
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    func uniqueBranchNameForWorktree(from baseBranch: String) -> String {
        let base = baseBranch.clean
        guard !base.isEmpty else { return baseBranch }
        var candidate = base
        var suffix = 2
        while localBranchExists(named: candidate) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    func removeWorktree(_ path: String, force: Bool = false) {
        var args = ["worktree", "remove"]
        if force { args.append("--force") }
        args.append(path)
        runGitAction(label: "Remover worktree", args: args)
    }

    func openWorktreeTerminal(_ worktree: WorktreeItem) {
        let url = URL(fileURLWithPath: worktree.path)
        let label = worktree.branch.isEmpty ? url.lastPathComponent : worktree.branch
        createTerminalSession(workingDirectory: url, label: label, worktreeID: worktree.id)
    }

    func openWorktreeInZion(_ worktree: WorktreeItem, navigateToCode: Bool = true, sectionAfterOpen: AppSection? = nil) {
        let url = URL(fileURLWithPath: worktree.path)
        nextSectionAfterRepositoryOpen = sectionAfterOpen
        openRepository(url)
        let label = worktree.branch.isEmpty ? url.lastPathComponent : worktree.branch
        if let existing = terminalSessions.first(where: { $0.workingDirectory.path == url.path }) {
            activateSession(existing)
        } else {
            createTerminalSession(workingDirectory: url, label: label, worktreeID: worktree.id)
        }
        if navigateToCode {
            navigateToCodeRequested = true
        }
    }

    func requestWorktreeRemoval(_ worktree: WorktreeItem) {
        guard !worktree.isMainWorktree else { return }
        let displayName = worktreeDisplayName(worktree)
        let branchRetentionHint = L10n("worktree.remove.branchRemains", displayName)

        if worktree.uncommittedCount > 0 || worktree.hasConflicts {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n("worktree.remove.pending.title")
            alert.informativeText = L10n("worktree.remove.pending.message", displayName) + "\n\n" + branchRetentionHint
            alert.addButton(withTitle: L10n("worktree.remove.discardAndRemove"))
            alert.addButton(withTitle: L10n("worktree.remove.withoutDiscard"))
            alert.addButton(withTitle: L10n("Cancelar"))

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                discardAllChangesAndRemoveWorktree(worktree)
            case .alertSecondButtonReturn:
                removeWorktreeAndCloseTerminal(worktree, force: true)
            default:
                return
            }
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n("Remover worktree")
        alert.informativeText = L10n("Deseja remover o worktree %@?", worktree.path) + "\n\n" + branchRetentionHint
        alert.addButton(withTitle: L10n("Remover"))
        alert.addButton(withTitle: L10n("Cancelar"))
        if alert.runModal() == .alertFirstButtonReturn {
            removeWorktreeAndCloseTerminal(worktree)
        }
    }

    func removeWorktreeAndCloseTerminal(_ worktree: WorktreeItem, force: Bool = false) {
        guard let repositoryURL else {
            lastError = GitClientError.repositoryNotSelected.localizedDescription
            return
        }

        var args = ["worktree", "remove"]
        if force { args.append("--force") }
        args.append(worktree.path)

        actionTask?.cancel()
        isBusy = true
        actionTask = Task {
            do {
                let _ = try await worker.runAction(args: args, in: repositoryURL)
                try Task.checkCancellation()
                let branch = worktree.branch.clean
                if !branch.isEmpty {
                    _ = try? await worker.runAction(args: ["branch", "-d", branch], in: repositoryURL)
                }
                closeTerminalSession(forWorktree: worktree.id)
                clearError()
                statusMessage = force
                    ? L10n("worktree.remove.forced.success", worktreeDisplayName(worktree))
                    : L10n("worktree.remove.success", worktreeDisplayName(worktree))
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

    func discardAllChangesAndRemoveWorktree(_ worktree: WorktreeItem) {
        guard let repositoryURL else {
            lastError = GitClientError.repositoryNotSelected.localizedDescription
            return
        }

        let targetURL = URL(fileURLWithPath: worktree.path)
        actionTask?.cancel()
        isBusy = true
        actionTask = Task {
            do {
                await abortInProgressIntegrationIfAny(in: targetURL)
                try await createDiscardSnapshotIfPossible(in: targetURL, tag: "zion-pre-discard-worktree")

                let _ = try await worker.runAction(args: ["reset", "--hard", "HEAD"], in: targetURL)
                let _ = try await worker.runAction(args: ["clean", "-fd"], in: targetURL)
                let _ = try await worker.runAction(args: ["worktree", "remove", worktree.path], in: repositoryURL)
                try Task.checkCancellation()
                let branch = worktree.branch.clean
                if !branch.isEmpty {
                    _ = try? await worker.runAction(args: ["branch", "-d", branch], in: repositoryURL)
                }
                closeTerminalSession(forWorktree: worktree.id)
                clearError()
                statusMessage = L10n("worktree.remove.discarded.success", worktreeDisplayName(worktree))
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

    func worktreeDisplayName(_ worktree: WorktreeItem) -> String {
        if !worktree.branch.clean.isEmpty {
            return worktree.branch
        }
        return URL(fileURLWithPath: worktree.path).lastPathComponent
    }

    // MARK: - Quick Worktree & Prune

    func quickCreateWorktree() {
        guard let repositoryURL else { return }
        let repoName = repositoryURL.lastPathComponent
        let parentDir = repositoryURL.deletingLastPathComponent()

        actionTask?.cancel()
        isBusy = true
        actionTask = Task {
            do {
                let branchListOutput = try await worker.runAction(args: ["branch", "--list", "--format=%(refname:short)"], in: repositoryURL)
                let tagListOutput = try await worker.runAction(args: ["tag", "--list"], in: repositoryURL)
                let existingRefs = Set(
                    (branchListOutput + "\n" + tagListOutput)
                        .split(separator: "\n")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                )
                var worktreeCounter = 1
                while FileManager.default.fileExists(atPath: parentDir.appendingPathComponent("\(repoName)-wt-\(worktreeCounter)").path)
                        || existingRefs.contains("wt-\(worktreeCounter)") {
                    worktreeCounter += 1
                }
                let wtPath = parentDir.appendingPathComponent("\(repoName)-wt-\(worktreeCounter)").path
                let branchName = "wt-\(worktreeCounter)"
                try Task.checkCancellation()
                let _ = try await worker.runAction(args: ["worktree", "add", "-b", branchName, wtPath], in: repositoryURL)
                try Task.checkCancellation()
                clearError()
                let wtSession = TerminalSession(workingDirectory: URL(fileURLWithPath: wtPath), label: branchName, worktreeID: wtPath)
                splitFocusedWithSession(wtSession, direction: .vertical)
                statusMessage = "Worktree criado: \(repoName)-wt-\(worktreeCounter)"
                refreshRepository(setBusy: true)
            } catch is CancellationError {
                isBusy = false
                return
            }
            catch { isBusy = false; handleError(error) }
        }
    }

    func pruneWorktrees() {
        runGitAction(label: "Worktree prune", args: ["worktree", "prune"])
    }

    func slugifiedWorktreeName(from input: String) -> String {
        let folded = input
            .clean
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        let mapped = folded.map { character -> Character in
            if character.isLetter || character.isNumber { return character }
            return "-"
        }

        var slug = String(mapped)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        while slug.hasPrefix(".") || slug.hasSuffix(".") {
            slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }
        return slug
    }

    func uniquePath(forBaseName baseName: String, in directory: URL) -> URL {
        var candidate = directory.appendingPathComponent(baseName)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(index)")
            index += 1
        }
        return candidate
    }

    func pruneMergedBranches() {
        actionTask?.cancel()
        isBusy = true

        let url = repositoryURL
        actionTask = Task {
            do {
                guard let url else { return }
                let baseRef = pruneMergeBaseRef()
                let result = try await worker.runAction(args: ["branch", "--merged", baseRef], in: url)
                let branchesToDelete = computeMergedBranchesToPrune(from: result, baseRef: baseRef)

                if branchesToDelete.isEmpty {
                    statusMessage = L10n("Nenhuma branch mesclada encontrada.")
                    isBusy = false
                    return
                }

                let _ = try await worker.runAction(args: ["branch", "-d"] + branchesToDelete, in: url)
                clearError()
                let list = branchesToDelete.joined(separator: ", ")
                statusMessage = L10n("Branches removidas: %@", list)
                refreshRepository(setBusy: true)
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    func pruneMergeBaseRef() -> String {
        let locals = Set(localBranchOptions)
        if locals.contains("main") { return "main" }
        if locals.contains("master") { return "master" }
        if locals.contains(currentBranch) { return currentBranch }
        return "HEAD"
    }

    func computeMergedBranchesToPrune(from output: String, baseRef: String) -> [String] {
        let protectedBranches = Set(["main", "master", "develop", "dev", baseRef, currentBranch])
        return output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.replacingOccurrences(of: "* ", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !protectedBranches.contains($0) }
    }

    func refreshMergedBranchesPreview() {
        guard let url = repositoryURL else {
            mergedBranchesPreview = []
            return
        }
        let baseRef = pruneMergeBaseRef()
        Task {
            let output = (try? await worker.runAction(args: ["branch", "--merged", baseRef], in: url)) ?? ""
            guard self.repositoryURL?.path == url.path else { return }
            self.mergedBranchesPreview = computeMergedBranchesToPrune(from: output, baseRef: baseRef)
        }
    }
}
