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

                await MainActor.run { currentBranch = localName }

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

    // MARK: - Multi-remote collision flows

    /// Switches an existing local branch's upstream to a different remote ref, then
    /// checks it out and pulls. Used when the user clicks a remote-branch pill whose
    /// local namesake currently tracks a different remote (e.g. local `main` tracks
    /// `origin/main`, user clicks `pivotree/main` and chooses "switch upstream").
    func switchUpstreamAndPull(localName: String, remoteTarget: String) {
        let cleanedLocal = localName.clean
        let cleanedRemote = remoteTarget.clean
        guard !cleanedLocal.isEmpty, !cleanedRemote.isEmpty else { return }
        guard !isBusy, activeGitActionToken == nil else { return }

        let actionToken = UUID()
        activeGitActionToken = actionToken
        isBusy = true
        armBusyWatchdog()

        let url = repositoryURL
        actionTask = Task {
            do {
                guard let url else { return }
                let _ = try await worker.runAction(
                    args: ["branch", "--set-upstream-to=\(cleanedRemote)", cleanedLocal],
                    in: url
                )
                let _ = try await worker.runAction(args: ["checkout", cleanedLocal], in: url)
                await MainActor.run { currentBranch = cleanedLocal }
                let _ = try await runActionWithCredentialRetry(
                    label: "Pull",
                    args: ["pull"],
                    in: url,
                    commandSummary: redactedGitCommandSummary(args: ["pull"])
                )
                clearError()
                statusMessage = L10n("checkout.multiRemote.upstream.switched.status", cleanedLocal, cleanedRemote)
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
                    divergenceResolution = buildDivergenceContext(branch: cleanedLocal, url: url)
                } else {
                    handleError(error)
                }
            }
        }
    }

    /// Creates a brand-new local branch that tracks the given remote ref and checks it out.
    /// Used when the user wants to keep the existing local namesake untouched and work
    /// from a parallel branch (e.g., `pivotree-main` tracking `pivotree/main`).
    func createTrackingBranch(newLocalName: String, remoteTarget: String) {
        let cleanedNew = newLocalName.clean
        let cleanedRemote = remoteTarget.clean
        guard !cleanedNew.isEmpty, !cleanedRemote.isEmpty else { return }
        guard !isBusy, activeGitActionToken == nil else { return }

        if localBranchExists(named: cleanedNew) {
            handleError(GitClientError.commandFailed(
                command: "checkout",
                message: L10n("checkout.multiRemote.newBranch.exists", cleanedNew)
            ))
            return
        }

        let actionToken = UUID()
        activeGitActionToken = actionToken
        isBusy = true
        armBusyWatchdog()

        let url = repositoryURL
        actionTask = Task {
            do {
                guard let url else { return }
                let _ = try await worker.runAction(
                    args: ["checkout", "-b", cleanedNew, "--track", cleanedRemote],
                    in: url
                )
                await MainActor.run { currentBranch = cleanedNew }
                clearError()
                statusMessage = L10n("checkout.multiRemote.newBranch.created", cleanedNew, cleanedRemote)
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
                handleError(error)
            }
        }
    }

    /// Returns the existing local branch's upstream when it differs from the supplied
    /// remote ref. Used by views to decide whether to surface the multi-remote dialog.
    func conflictingUpstream(forLocalName localName: String, clickedRemote: String) -> String? {
        guard let local = branchInfos.first(where: { !$0.isRemote && $0.name == localName }) else { return nil }
        let upstream = local.upstream.clean
        guard !upstream.isEmpty, upstream != clickedRemote else { return nil }
        return upstream
    }
}
