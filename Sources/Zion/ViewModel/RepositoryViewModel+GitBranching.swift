import Foundation
import SwiftUI

extension RepositoryViewModel {

    // MARK: - Divergence Resolution

    func resolveDivergence(_ resolution: DivergenceResolution, context: DivergenceContext) {
        divergenceResolution = nil

        switch resolution {
        case .rebase:
            runGitAction(label: "Pull --rebase", args: ["pull", "--rebase"])
        case .merge:
            runGitAction(label: "Pull --no-rebase", args: ["pull", "--no-rebase"])
        case .forceAlign:
            guard let url = repositoryURL else { return }
            let remoteBranch = resolveUpstreamRef(for: context.branch) ?? "origin/\(context.branch)"
            runDestructiveGitAction(
                label: "Reset --hard",
                args: ["reset", "--hard", remoteBranch],
                operationTag: "reset-hard",
                targetHint: remoteBranch
            )
            _ = url // suppress unused warning
        }
    }

    func isDivergentBranchError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("divergent branches")
            || message.contains("need to specify how to reconcile")
    }

    func buildDivergenceContext(branch: String, url: URL?) -> DivergenceContext {
        DivergenceContext(
            branch: branch,
            localAhead: aheadRemoteCount,
            remoteAhead: behindRemoteCount
        )
    }

    func resolveUpstreamRef(for branch: String) -> String? {
        branchInfos.first(where: { $0.name == branch })?.upstream
    }

    // MARK: - Push Branch

    func pushBranch(_ branch: String, to remote: String, setUpstream: Bool, mode: PushMode) {
        let branchName = branch.clean
        let remoteName = remote.clean
        guard !branchName.isEmpty, !remoteName.isEmpty else { return }

        var args = ["push"]
        if setUpstream {
            args.append("--set-upstream")
        }
        switch mode {
        case .normal:
            break
        case .forceWithLease:
            args.append("--force-with-lease")
        case .force:
            args.append("--force")
        }
        args.append(remoteName)
        args.append("\(branchName):\(branchName)")
        runGitAction(label: "Push branch", args: args)
    }

    // MARK: - Branch Operations

    func createBranch() {
        let target = branchInput.clean
        guard !target.isEmpty else { return }
        createBranch(named: target, from: "HEAD", andCheckout: true)
    }

    func createBranch(named name: String, from startPoint: String, andCheckout: Bool = true) {
        let targetName = name.clean
        let targetPoint = startPoint.clean
        guard !targetName.isEmpty, !targetPoint.isEmpty else { return }
        if andCheckout {
            runGitAction(label: "Nova branch", args: ["checkout", "-b", targetName, targetPoint])
        } else {
            runGitAction(label: "Nova branch", args: ["branch", targetName, targetPoint])
        }
    }

    func mergeBranch() {
        let target = branchInput.clean
        guard !target.isEmpty else { return }
        mergeBranch(named: target)
    }

    func mergeBranch(named branch: String) {
        let target = branch.clean
        guard !target.isEmpty else { return }
        runDestructiveGitAction(label: "Merge", args: ["merge", target], operationTag: "merge", targetHint: target)
    }

    func pullIntoCurrent(fromRemoteBranch remoteBranch: String) {
        let target = remoteBranch.clean
        guard !target.isEmpty else { return }
        let components = target.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
        guard components.count == 2 else { return }
        runGitAction(label: "Pull branch", args: ["pull", String(components[0]), String(components[1])])
    }

    func deleteRemoteBranch(reference: String) {
        let target = reference.clean
        guard isRemoteRefName(target) else { return }
        let parts = target.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return }
        runGitAction(label: "Delete remote branch", args: ["push", String(parts[0]), "--delete", String(parts[1])])
    }

    func renameBranch(oldName: String, newName: String) {
        let old = oldName.clean
        let new = newName.clean
        guard !old.isEmpty, !new.isEmpty else { return }
        runGitAction(label: "Renomear branch", args: ["branch", "-m", old, new])
    }

    func deleteLocalBranch(_ branch: String, force: Bool) {
        let name = branch.clean
        guard !name.isEmpty else { return }
        guard let repositoryURL else {
            lastError = GitClientError.repositoryNotSelected.localizedDescription
            return
        }

        actionTask?.cancel()
        let actionToken = UUID()
        activeGitActionToken = actionToken
        isBusy = true

        let label = "Delete local branch"
        let deleteArgs = ["branch", force ? "-D" : "-d", name]
        let commandSummary = redactedGitCommandSummary(args: deleteArgs)
        logger.log(.git, commandSummary, context: label)

        actionTask = Task {
            do {
                // Always prune first so stale worktree metadata doesn't block deletion
                // after a worktree folder was removed.
                _ = try? await worker.runAction(args: ["worktree", "prune"], in: repositoryURL)
                let output = try await worker.runAction(args: deleteArgs, in: repositoryURL)
                try Task.checkCancellation()

                clearError()
                if output.isEmpty {
                    statusMessage = "\(label) executado com sucesso."
                } else {
                    statusMessage = "\(label): \(output.prefix(240))"
                }
                logger.log(.git, "\(label) OK", context: commandSummary)
                guard activeGitActionToken == actionToken else { return }
                activeGitActionToken = nil
                refreshRepository(setBusy: true, origin: .gitAction)
            } catch is CancellationError {
                guard activeGitActionToken == actionToken else { return }
                activeGitActionToken = nil
                isBusy = false
                logger.log(.info, "\(label) cancelled", context: commandSummary, source: #function)
                return
            } catch {
                guard activeGitActionToken == actionToken else { return }
                activeGitActionToken = nil
                isBusy = false
                logger.log(.error, error.localizedDescription, context: commandSummary)
                handleError(error)
            }
        }
    }

    func branchInfo(named name: String) -> BranchInfo? {
        branchInfos.first(where: { $0.name == name })
    }

    func createArchive(reference: String, outputPath: String) {
        let ref = reference.clean
        let path = outputPath.clean
        guard !ref.isEmpty, !path.isEmpty else { return }
        runGitAction(label: "Create archive", args: ["archive", "--format=zip", "--output", path, ref])
    }
}
