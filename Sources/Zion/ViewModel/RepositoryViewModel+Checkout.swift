import Foundation
import SwiftUI

extension RepositoryViewModel {

    // MARK: - Checkout

    func checkout(reference: String) {
        let target = reference.clean
        DiagnosticLogger.shared.log(.info, "checkout ENTER", context: "ref=\(reference) target=\(target) isBusy=\(isBusy) activeToken=\(activeGitActionToken != nil) currentBranch=\(currentBranch)", source: "checkout(reference:)")
        guard !target.isEmpty else {
            DiagnosticLogger.shared.log(.warn, "checkout BAIL: empty target", source: "checkout(reference:)")
            return
        }
        guard !isBusy else {
            DiagnosticLogger.shared.log(.warn, "checkout BAIL: isBusy", source: "checkout(reference:)")
            return
        }
        guard activeGitActionToken == nil else {
            DiagnosticLogger.shared.log(.warn, "checkout BAIL: activeGitActionToken", source: "checkout(reference:)")
            return
        }

        // Determine local branch name if it's a remote ref
        var localName = target
        for remote in remotes {
            if target.hasPrefix("\(remote.name)/") {
                localName = String(target.dropFirst(remote.name.count + 1))
                break
            }
        }

        if localName == "HEAD" {
            DiagnosticLogger.shared.log(.warn, "checkout BAIL: symbolic HEAD ref", context: target, source: "checkout(reference:)")
            return
        }

        if localName == currentBranch {
            DiagnosticLogger.shared.log(.warn, "checkout BAIL: already on branch", context: localName, source: "checkout(reference:)")
            return
        }

        if localBranchExists(named: localName) {
            if let occupied = worktrees.first(where: { !$0.isCurrent && $0.branch.clean == localName }) {
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = L10n("checkout.worktree.inUse.title")
                alert.informativeText = L10n("checkout.worktree.inUse.message", localName, occupied.path)
                alert.addButton(withTitle: L10n("checkout.worktree.inUse.open"))
                alert.addButton(withTitle: L10n("Cancelar"))
                if alert.runModal() == .alertFirstButtonReturn {
                    openWorktreeInZion(occupied, navigateToCode: false, sectionAfterOpen: .graph)
                    statusMessage = L10n("checkout.worktree.redirected", localName)
                }
                return
            }
            runGitAction(
                label: "Checkout",
                args: ["checkout", "--quiet", localName],
                refreshOptions: .critical,
                scheduleFullRefreshAfterCompletion: true,
                refreshSetBusy: false,
                onCommandSuccess: { [weak self] in
                    self?.currentBranch = localName
                }
            )
        } else if isRemoteRefName(target) {
            runGitAction(
                label: "Checkout",
                args: ["checkout", "--quiet", "-t", target],
                refreshOptions: .critical,
                scheduleFullRefreshAfterCompletion: true,
                refreshSetBusy: false,
                onCommandSuccess: { [weak self] in
                    self?.currentBranch = localName
                }
            )
        } else {
            runGitAction(
                label: "Checkout",
                args: ["checkout", "--quiet", target],
                refreshOptions: .critical,
                scheduleFullRefreshAfterCompletion: true,
                refreshSetBusy: false,
                onCommandSuccess: { [weak self] in
                    self?.currentBranch = localName
                }
            )
        }
    }

    func checkoutAndPull(reference: String) {
        let target = reference.clean
        guard !target.isEmpty else { return }
        guard !isBusy else { return }

        // Match checkout() behavior: if this local branch belongs to another
        // worktree, offer to jump there instead of surfacing a checkout error.
        var localName = target
        for remote in remotes {
            if target.hasPrefix("\(remote.name)/") {
                localName = String(target.dropFirst(remote.name.count + 1))
                break
            }
        }
        if localBranchExists(named: localName) {
            if let occupied = worktrees.first(where: { !$0.isCurrent && $0.branch.clean == localName }) {
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = L10n("checkout.worktree.inUse.title")
                alert.informativeText = L10n("checkout.worktree.inUse.message", localName, occupied.path)
                alert.addButton(withTitle: L10n("checkout.worktree.inUse.open"))
                alert.addButton(withTitle: L10n("Cancelar"))
                if alert.runModal() == .alertFirstButtonReturn {
                    openWorktreeInZion(occupied, navigateToCode: false, sectionAfterOpen: .graph)
                    statusMessage = L10n("checkout.worktree.redirected", localName)
                }
                return
            }
        }

        guard activeGitActionToken == nil else { return }
        let actionToken = UUID()
        activeGitActionToken = actionToken
        isBusy = true
        armBusyWatchdog()

        let url = repositoryURL
        actionTask = Task {
            do {
                guard let url else { return }

                // 1. Determine local branch name and full remote target
                var localName = target
                var remoteTarget = target

                // Check if target is a known remote branch (e.g. origin/develop)
                for remote in remotes {
                    if target.hasPrefix("\(remote.name)/") {
                        localName = String(target.dropFirst(remote.name.count + 1))
                        remoteTarget = target
                        break
                    }
                }

                if localName == "HEAD" {
                    DiagnosticLogger.shared.log(.warn, "checkoutAndPull BAIL: symbolic HEAD ref", context: target, source: "checkoutAndPull(reference:)")
                    activeGitActionToken = nil
                    isBusy = false
                    disarmBusyWatchdog()
                    return
                }

                // 2. Perform Smart Checkout
                if localBranchExists(named: localName) {
                    // Already exists locally, just checkout and pull
                    let _ = try await worker.runAction(args: ["checkout", localName], in: url)
                } else if isRemoteRefName(remoteTarget) {
                    // New local branch tracking remote
                    let _ = try await worker.runAction(args: ["checkout", "-t", remoteTarget], in: url)
                } else {
                    // Fallback
                    let _ = try await worker.runAction(args: ["checkout", target], in: url)
                }

                // 3. Pull changes
                let _ = try await runActionWithCredentialRetry(
                    label: "Pull",
                    args: ["pull"],
                    in: url,
                    commandSummary: redactedGitCommandSummary(args: ["pull"])
                )

                clearError()
                statusMessage = L10n("Checkout e Pull concluídos para %@", localName)
                guard activeGitActionToken == actionToken else { return }
                activeGitActionToken = nil
                refreshRepository(
                    setBusy: true,
                    options: .critical,
                    origin: .gitAction,
                    onFinish: { [weak self] in
                        self?.refreshRepository(setBusy: false, options: .full, origin: .gitAction)
                    }
                )
            } catch is CancellationError {
                guard activeGitActionToken == actionToken else { return }
                activeGitActionToken = nil
                isBusy = false
                disarmBusyWatchdog()
            } catch {
                guard activeGitActionToken == actionToken else { return }
                activeGitActionToken = nil
                isBusy = false
                disarmBusyWatchdog()

                if isDivergentBranchError(error) {
                    let context = buildDivergenceContext(branch: localName, url: url)
                    divergenceResolution = context
                } else {
                    handleError(error)
                }
            }
        }
    }

    func checkoutBranch() {
        let target = branchInput.clean
        guard !target.isEmpty else { return }
        checkout(reference: target)
    }
}
