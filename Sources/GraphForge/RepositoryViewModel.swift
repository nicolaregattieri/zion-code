import Foundation
import SwiftUI

@MainActor
final class RepositoryViewModel: ObservableObject {
    @Published var repositoryURL: URL?
    @Published var currentBranch: String = "-"
    @Published var headShortHash: String = "-"
    @Published var commits: [Commit] = []
    @Published var selectedCommitID: String?
    @Published var commitDetails: String = "Selecione um commit para ver os detalhes."
    @Published var branches: [String] = []
    @Published var branchInfos: [BranchInfo] = []
    @Published var branchTree: [BranchTreeNode] = []
    @Published var focusedBranch: String?
    @Published var inferBranchOrigins: Bool = false
    @Published var hasMoreCommits: Bool = false
    @Published var tags: [String] = []
    @Published var stashes: [String] = []
    @Published var selectedStash: String = ""
    @Published var worktrees: [WorktreeItem] = []
    @Published var statusMessage: String = "Selecione um repositorio para iniciar."
    @Published var lastError: String?
    @Published var isBusy: Bool = false
    @Published var hasConflicts: Bool = false
    @Published var isMerging: Bool = false
    @Published var isRebasing: Bool = false
    @Published var isCherryPicking: Bool = false
    @Published var isGitRepository: Bool = true
    @Published var uncommittedChanges: [String] = []
    @Published var uncommittedCount: Int = 0

    @Published var branchInput: String = ""
    @Published var tagInput: String = ""
    @Published var stashMessageInput: String = ""
    @Published var cherryPickInput: String = ""
    @Published var resetTargetInput: String = "HEAD~1"
    @Published var rebaseTargetInput: String = ""
    @Published var worktreePathInput: String = ""
    @Published var worktreeBranchInput: String = ""
    @Published var remotes: [RemoteInfo] = []
    @Published var remoteNameInput: String = "origin"
    @Published var remoteURLInput: String = ""
    @Published var commitMessageInput: String = ""

    @AppStorage("graphforge.recentRepositories") private var recentReposData: Data = Data()
    @Published var recentRepositories: [URL] = []

    private let git = GitClient()
    private let worker = RepositoryWorker()
    
    private let defaultCommitLimitAll = 700
    private let defaultCommitLimitFocused = 450
    private let commitPageSize = 300
    private let maxCommitLimit = 5000
    private var commitLimit = 700
    private var refreshRequestID = UUID()
    private var detailsRequestID = UUID()
    private var refreshTask: Task<Void, Never>?
    private var detailsTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?

    var maxLaneCount: Int {
        let maxLane = commits
            .flatMap { [$0.lane] + $0.incomingLanes + $0.outgoingLanes + $0.outgoingEdges.map(\.to) }
            .max() ?? 0
        return maxLane + 1
    }

    func openRepository(_ url: URL) {
        repositoryURL = url
        saveRecentRepository(url)
        commitLimit = defaultCommitLimit(for: nil)
        if worktreePathInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            worktreePathInput = url.deletingLastPathComponent().appendingPathComponent("new-worktree").path
        }
        refreshRepository()
    }

    func loadRecentRepositories() {
        if let urls = try? JSONDecoder().decode([URL].self, from: recentReposData) {
            recentRepositories = urls
        }
    }

    private func saveRecentRepository(_ url: URL) {
        var current = (try? JSONDecoder().decode([URL].self, from: recentReposData)) ?? []
        current.removeAll { $0 == url }
        current.insert(url, at: 0)
        let limited = Array(current.prefix(5))
        if let encoded = try? JSONEncoder().encode(limited) {
            recentReposData = encoded
            recentRepositories = limited
        }
    }

    func refreshRepository() {
        refreshRepository(setBusy: true)
    }

    func selectCommit(_ commitID: String?) {
        selectedCommitID = commitID
        loadCommitDetails(for: commitID)
    }

    func fetch() { runGitAction(label: "Fetch", args: ["fetch", "--all", "--prune"]) }
    func pull() { runGitAction(label: "Pull", args: ["pull", "--ff-only"]) }
    func push() { runGitAction(label: "Push", args: ["push"]) }

    func setInferBranchOrigins(_ enabled: Bool) {
        inferBranchOrigins = enabled
        if repositoryURL != nil {
            refreshRepository()
        }
    }

    func setBranchFocus(_ branch: String?) {
        let normalized = branch?.clean
        focusedBranch = normalized?.isEmpty == true ? nil : normalized
        commitLimit = defaultCommitLimit(for: focusedBranch)
        refreshCommitsOnly()
    }

    func loadMoreCommits() {
        guard repositoryURL != nil, hasMoreCommits else { return }
        let nextLimit = min(maxCommitLimit, commitLimit + commitPageSize)
        guard nextLimit != commitLimit else { return }
        commitLimit = nextLimit
        refreshCommitsOnly()
    }

    func checkout(reference: String) {
        let target = reference.clean
        guard !target.isEmpty else { return }

        if isRemoteRefName(target), !localBranchExists(named: target) {
            runGitAction(label: "Checkout", args: ["checkout", "-t", target])
            return
        }
        runGitAction(label: "Checkout", args: ["checkout", target])
    }

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

    func checkoutBranch() {
        let target = branchInput.clean
        guard !target.isEmpty else { return }
        checkout(reference: target)
    }

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
        runGitAction(label: "Merge", args: ["merge", target])
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

    func rebaseOntoTarget() {
        let target = rebaseTargetInput.clean
        guard !target.isEmpty else { return }
        runGitAction(label: "Rebase", args: ["rebase", target])
    }

    func rebaseCurrentBranch(onto reference: String) {
        let target = reference.clean
        guard !target.isEmpty else { return }
        runGitAction(label: "Rebase", args: ["rebase", target])
    }

    func cherryPick() {
        let target = cherryPickInput.clean
        guard !target.isEmpty else { return }
        cherryPick(commitHash: target)
    }

    func cherryPick(commitHash: String) {
        let target = commitHash.clean
        guard !target.isEmpty else { return }
        runGitAction(label: "Cherry-pick", args: ["cherry-pick", target])
    }

    func revert(commitHash: String) {
        let target = commitHash.clean
        guard !target.isEmpty else { return }
        runGitAction(label: "Revert", args: ["revert", "--no-edit", target])
    }

    func hardReset() {
        let target = resetTargetInput.clean
        guard !target.isEmpty else { return }
        hardReset(to: target)
    }

    func hardReset(to target: String) {
        let cleanedTarget = target.clean
        guard !cleanedTarget.isEmpty else { return }
        runGitAction(label: "Reset --hard", args: ["reset", "--hard", cleanedTarget])
    }

    func createTag() {
        let target = tagInput.clean
        guard !target.isEmpty else { return }
        createTag(named: target, at: "HEAD")
    }

    func createTag(named name: String, at target: String) {
        let tagName = name.clean
        let tagTarget = target.clean
        guard !tagName.isEmpty, !tagTarget.isEmpty else { return }
        runGitAction(label: "Criar tag", args: ["tag", tagName, tagTarget])
    }

    func deleteTag() {
        let target = tagInput.clean
        guard !target.isEmpty else { return }
        runGitAction(label: "Remover tag", args: ["tag", "-d", target])
    }

    func createStash() {
        let message = stashMessageInput.clean
        createStash(message: message.isEmpty ? nil : message)
    }

    func createStash(message: String?) {
        let cleanedMessage = message?.clean ?? ""
        if cleanedMessage.isEmpty {
            runGitAction(label: "Stash", args: ["stash", "push"])
        } else {
            runGitAction(label: "Stash", args: ["stash", "push", "-m", cleanedMessage])
        }
    }

    func applySelectedStash() {
        guard let stashRef = selectedStashReference else { return }
        runGitAction(label: "Apply stash", args: ["stash", "apply", stashRef])
    }

    func popSelectedStash() {
        guard let stashRef = selectedStashReference else { return }
        runGitAction(label: "Pop stash", args: ["stash", "pop", stashRef])
    }

    func dropSelectedStash() {
        guard let stashRef = selectedStashReference else { return }
        runGitAction(label: "Drop stash", args: ["stash", "drop", stashRef])
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

    func removeWorktree(_ path: String) {
        runGitAction(label: "Remover worktree", args: ["worktree", "remove", path])
    }

    func pruneWorktrees() {
        runGitAction(label: "Worktree prune", args: ["worktree", "prune"])
    }

    func pruneMergedBranches() {
        actionTask?.cancel()
        isBusy = true
        
        let url = repositoryURL
        actionTask = Task {
            do {
                guard let url else { return }
                // 1. Get branches merged into main
                let result = try await worker.runAction(args: ["branch", "--merged", "main"], in: url)
                let branchesToDelete = result.split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && !$0.hasPrefix("*") && $0 != "main" && $0 != "master" }
                
                if branchesToDelete.isEmpty {
                    statusMessage = L10n("Nenhuma branch mesclada encontrada.")
                    isBusy = false
                    return
                }
                
                // 2. Delete them
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

    func initRepository() {
        runGitAction(label: "Git Init", args: ["init"])
    }

    func addRemote() {
        let name = remoteNameInput.clean
        let url = remoteURLInput.clean
        guard !name.isEmpty, !url.isEmpty else { return }
        runGitAction(label: "Add Remote", args: ["remote", "add", name, url])
    }

    func removeRemote(named name: String) {
        runGitAction(label: "Remove Remote", args: ["remote", "remove", name])
    }

    func testRemote(named name: String) {
        runGitAction(label: "Test Remote", args: ["ls-remote", "--exit-code", name])
    }

    func commit(message: String) {
        let msg = message.clean
        guard !msg.isEmpty else { return }
        
        actionTask?.cancel()
        isBusy = true
        
        let url = repositoryURL
        actionTask = Task {
            do {
                guard let url else { return }
                // 1. Stage all changes if nothing is staged, otherwise just commit what's staged
                // To keep it simple and match user expectation of "Fazer Commit" button:
                // If the user hasn't manually staged anything, we stage everything.
                let status = try await worker.runAction(args: ["status", "--porcelain"], in: url)
                let hasStaged = status.split(separator: "\n").contains { line in
                    let first = line.prefix(1)
                    return first != " " && first != "?"
                }
                
                if !hasStaged {
                    let _ = try await worker.runAction(args: ["add", "-A"], in: url)
                }
                
                // 2. Commit
                let _ = try await worker.runAction(args: ["commit", "-m", msg], in: url)
                
                clearError()
                statusMessage = L10n("Commit realizado com sucesso.")
                commitMessageInput = ""
                refreshRepository(setBusy: true)
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    func stageFile(_ path: String) {
        runGitAction(label: "Stage", args: ["add", path])
    }

    func unstageFile(_ path: String) {
        runGitAction(label: "Unstage", args: ["reset", "HEAD", "--", path])
    }

    func stageAllFiles() {
        runGitAction(label: "Stage All", args: ["add", "-A"])
    }

    func unstageAllFiles() {
        runGitAction(label: "Unstage All", args: ["reset", "HEAD", "--", "."])
    }

    func renameRemote(oldName: String, newName: String) {
        runGitAction(label: "Rename Remote", args: ["remote", "rename", oldName, newName])
    }

    func abortMerge() { runGitAction(label: "Abort Merge", args: ["merge", "--abort"]) }
    func abortRebase() { runGitAction(label: "Abort Rebase", args: ["rebase", "--abort"]) }
    func abortCherryPick() { runGitAction(label: "Abort Cherry-pick", args: ["cherry-pick", "--abort"]) }

    func createArchive(reference: String, outputPath: String) {
        let ref = reference.clean
        let path = outputPath.clean
        guard !ref.isEmpty, !path.isEmpty else { return }
        runGitAction(label: "Create archive", args: ["archive", "--format=zip", "--output", path, ref])
    }

    func deleteLocalBranch(_ branch: String, force: Bool) {
        let name = branch.clean
        guard !name.isEmpty else { return }
        runGitAction(
            label: "Delete local branch",
            args: ["branch", force ? "-D" : "-d", name]
        )
    }

    func branchInfo(named name: String) -> BranchInfo? {
        branchInfos.first(where: { $0.name == name })
    }

    func localBranchExists(named name: String) -> Bool {
        branchInfos.contains(where: { !$0.isRemote && $0.name == name })
    }

    func isRemoteRefName(_ value: String) -> Bool {
        branchInfos.contains(where: { $0.isRemote && $0.name == value })
    }

    private var selectedStashReference: String? {
        let value = selectedStash.clean
        guard !value.isEmpty else { return nil }
        return value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init)
    }

    private func refreshCommitsOnly() {
        guard let repositoryURL else {
            lastError = GitClientError.repositoryNotSelected.localizedDescription
            hasMoreCommits = false
            return
        }

        refreshTask?.cancel()
        let requestID = UUID()
        refreshRequestID = requestID
        isBusy = true

        let focusedBranchSnapshot = focusedBranch
        let selectedCommitSnapshot = selectedCommitID
        let commitLimitSnapshot = commitLimit

        refreshTask = Task {
            do {
                let payload = try await worker.loadCommits(
                    in: repositoryURL,
                    reference: focusedBranchSnapshot,
                    selectedCommitID: selectedCommitSnapshot,
                    limit: commitLimitSnapshot
                )
                try Task.checkCancellation()
                guard refreshRequestID == requestID else { return }

                clearError()
                commits = payload.commits
                hasMoreCommits = payload.hasMore
                selectedCommitID = payload.selectedCommitID
                if let focusedBranchSnapshot {
                    statusMessage = L10n("Filtro de branch ativo: %@ · %@ commits", focusedBranchSnapshot, "\(payload.commits.count)")
                } else {
                    statusMessage = L10n("Visualizando todas as branches · %@ commits", "\(payload.commits.count)")
                }
                isBusy = false
                loadCommitDetails(for: payload.selectedCommitID)
            } catch is CancellationError {
                return
            } catch {
                guard refreshRequestID == requestID else { return }
                isBusy = false
                handleError(error)
            }
        }
    }

    private func refreshRepository(setBusy: Bool) {
        guard let repositoryURL else {
            lastError = GitClientError.repositoryNotSelected.localizedDescription
            hasMoreCommits = false
            return
        }

        refreshTask?.cancel()
        let requestID = UUID()
        refreshRequestID = requestID
        if setBusy {
            isBusy = true
        }

        let focusedBranchSnapshot = focusedBranch
        let selectedCommitSnapshot = selectedCommitID
        let selectedStashSnapshot = selectedStash
        let inferOrigins = inferBranchOrigins
        let commitLimitSnapshot = commitLimit

        refreshTask = Task {
            do {
                let payload = try await worker.loadRepository(
                    in: repositoryURL,
                    focusedBranch: focusedBranchSnapshot,
                    selectedCommitID: selectedCommitSnapshot,
                    selectedStash: selectedStashSnapshot,
                    inferOrigins: inferOrigins,
                    limit: commitLimitSnapshot
                )
                try Task.checkCancellation()
                guard refreshRequestID == requestID else { return }

                clearError()
                currentBranch = payload.currentBranch
                headShortHash = payload.headShortHash
                branchInfos = payload.branchInfos
                branches = payload.branches
                focusedBranch = payload.focusedBranch
                branchTree = payload.branchTree
                tags = payload.tags
                stashes = payload.stashes
                selectedStash = payload.selectedStash
                worktrees = payload.worktrees
                remotes = payload.remotes
                commits = payload.commits
                hasMoreCommits = payload.hasMoreCommits
                selectedCommitID = payload.selectedCommitID
                hasConflicts = payload.hasConflicts
                isMerging = payload.isMerging
                isRebasing = payload.isRebasing
                isCherryPicking = payload.isCherryPicking
                isGitRepository = payload.isGitRepository
                uncommittedChanges = payload.uncommittedChanges
                uncommittedCount = payload.uncommittedCount
                statusMessage = L10n("Repositorio carregado: %@ · %@ commits", repositoryURL.lastPathComponent, "\(payload.commits.count)")
                if setBusy {
                    isBusy = false
                }
                loadCommitDetails(for: payload.selectedCommitID)
            } catch is CancellationError {
                return
            } catch {
                guard refreshRequestID == requestID else { return }
                if setBusy {
                    isBusy = false
                }
                handleError(error)
            }
        }
    }

    private func runGitAction(label: String, args: [String]) {
        guard let repositoryURL else {
            lastError = GitClientError.repositoryNotSelected.localizedDescription
            return
        }

        actionTask?.cancel()
        isBusy = true

        actionTask = Task {
            do {
                let output = try await worker.runAction(args: args, in: repositoryURL)
                try Task.checkCancellation()

                clearError()
                if output.isEmpty {
                    statusMessage = "\(label) executado com sucesso."
                } else {
                    statusMessage = "\(label): \(output.prefix(240))"
                }
                refreshRepository(setBusy: true)
            } catch is CancellationError {
                return
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    private func loadCommitDetails(for commitID: String?) {
        guard let repositoryURL else {
            commitDetails = "Selecione um repositorio Git."
            return
        }

        guard let commitID else {
            commitDetails = "Selecione um commit para ver os detalhes."
            return
        }

        detailsTask?.cancel()
        let requestID = UUID()
        detailsRequestID = requestID
        commitDetails = "Carregando detalhes do commit..."

        detailsTask = Task {
            do {
                let details = try await worker.loadCommitDetails(in: repositoryURL, commitID: commitID)
                try Task.checkCancellation()
                guard detailsRequestID == requestID else { return }
                commitDetails = details
            } catch is CancellationError {
                return
            } catch {
                guard detailsRequestID == requestID else { return }
                commitDetails = error.localizedDescription
            }
        }
    }

    private func defaultCommitLimit(for reference: String?) -> Int {
        if let reference, !reference.clean.isEmpty {
            return defaultCommitLimitFocused
        }
        return defaultCommitLimitAll
    }

    private func clearError() {
        lastError = nil
    }

    private func handleError(_ error: Error) {
        lastError = error.localizedDescription
        statusMessage = error.localizedDescription
    }
}
