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
    @Published var selectedChangeFile: String?
    @Published var currentFileDiff: String = ""
    
    // Vibe Code state
    @Published var repositoryFiles: [FileItem] = []
    @Published var selectedCodeFile: FileItem?
    @Published var codeFileContent: String = ""
    @Published var selectedTheme: EditorTheme = .dracula
    @Published var expandedPaths: Set<String> = []

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
    @Published var amendLastCommit: Bool = false
    @Published var isTypingQuickly: Bool = false
    @Published var shouldClosePopovers: Bool = false
    @Published var debugLog: String = "Debug log initialized...\n"

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
        refreshFileTree()
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

    func selectChangeFile(_ file: String?) {
        selectedChangeFile = file
        if let file {
            loadDiff(for: file)
        } else {
            currentFileDiff = ""
        }
    }

    // MARK: - Vibe Code Methods

    func refreshFileTree() {
        guard let url = repositoryURL else { return }
        Task {
            let files = await loadFiles(at: url)
            repositoryFiles = files
        }
    }

    private func loadFiles(at url: URL) async -> [FileItem] {
        let fm = FileManager.default
        do {
            let contents = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            var items: [FileItem] = []
            for item in contents {
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let children = isDir ? await loadFiles(at: item) : nil
                items.append(FileItem(url: item, isDirectory: isDir, children: children?.sorted(by: { $0.name.lowercased() < $1.name.lowercased() })))
            }
            return items.sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.lowercased() < b.name.lowercased()
            }
        } catch {
            return []
        }
    }

    func selectCodeFile(_ item: FileItem) {
        guard !item.isDirectory else { return }
        selectedCodeFile = item
        do {
            codeFileContent = try String(contentsOf: item.url, encoding: .utf8)
        } catch {
            codeFileContent = "Erro ao ler arquivo: \(error.localizedDescription)"
        }
    }

    func toggleExpansion(for path: String) {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
        } else {
            expandedPaths.insert(path)
        }
    }

    func saveCurrentCodeFile() {
        guard let item = selectedCodeFile else { return }
        do {
            try codeFileContent.write(to: item.url, atomically: true, encoding: .utf8)
            statusMessage = L10n("Arquivo salvo: %@", item.name)
            refreshRepository() // Refresh to see changes in Git
        } catch {
            lastError = "Erro ao salvar: \(error.localizedDescription)"
        }
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

        // Determine local branch name if it's a remote ref
        var localName = target
        for remote in remotes {
            if target.hasPrefix("\(remote.name)/") {
                localName = String(target.dropFirst(remote.name.count + 1))
                break
            }
        }

        if localBranchExists(named: localName) {
            runGitAction(label: "Checkout", args: ["checkout", localName])
        } else if isRemoteRefName(target) {
            runGitAction(label: "Checkout", args: ["checkout", "-t", target])
        } else {
            runGitAction(label: "Checkout", args: ["checkout", target])
        }
    }

    func checkoutAndPull(reference: String) {
        let target = reference.clean
        guard !target.isEmpty else { return }
        
        actionTask?.cancel()
        isBusy = true
        
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
                let _ = try await worker.runAction(args: ["pull"], in: url)
                
                clearError()
                statusMessage = L10n("Checkout e Pull concluídos para %@", localName)
                refreshRepository(setBusy: true)
            } catch {
                isBusy = false
                handleError(error)
            }
        }
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

    func resetToCommit(_ commitID: String, hard: Bool) {
        let args = hard ? ["reset", "--hard", commitID] : ["reset", "--soft", commitID]
        runGitAction(label: hard ? "Reset --hard" : "Reset --soft", args: args)
    }

    func discardChanges(in path: String) {
        let file = path.trimmingCharacters(in: .whitespaces)
        runGitAction(label: "Discard", args: ["checkout", "--", file])
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
        Task {
            let ref = await resolveStashReference(selectedStash)
            guard let ref else { return }
            runGitAction(label: "Apply stash", args: ["stash", "apply", ref])
        }
    }

    func popSelectedStash() {
        Task {
            let ref = await resolveStashReference(selectedStash)
            guard let ref else { return }
            runGitAction(label: "Pop stash", args: ["stash", "pop", ref])
        }
    }

    func dropSelectedStash() {
        Task {
            let ref = await resolveStashReference(selectedStash)
            guard let ref else { return }
            runGitAction(label: "Drop stash", args: ["stash", "drop", ref])
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
        let shouldAmend = amendLastCommit
        
        actionTask = Task {
            do {
                guard let url else { return }
                
                // 1. Always stage everything first for a guaranteed "Quick Commit"
                // This handles both modified and untracked files.
                let _ = try await worker.runAction(args: ["add", "-A"], in: url)
                
                // 2. Prepare commit arguments
                var commitArgs = ["commit", "-m", msg]
                if shouldAmend {
                    commitArgs.append("--amend")
                }
                
                // 3. Execute commit
                let _ = try await worker.runAction(args: commitArgs, in: url)
                
                clearError()
                statusMessage = shouldAmend ? L10n("Commit corrigido com sucesso.") : L10n("Commit realizado com sucesso.")
                commitMessageInput = ""
                amendLastCommit = false
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

    func addToGitIgnore(path: String) {
        guard let url = repositoryURL else { return }
        let gitIgnoreURL = url.appendingPathComponent(".gitignore")
        
        actionTask?.cancel()
        isBusy = true
        
        actionTask = Task {
            do {
                var content = ""
                if FileManager.default.fileExists(atPath: gitIgnoreURL.path) {
                    content = try String(contentsOf: gitIgnoreURL, encoding: .utf8)
                }
                
                if !content.contains(path) {
                    if !content.isEmpty && !content.hasSuffix("\n") {
                        content += "\n"
                    }
                    content += "\(path)\n"
                    try content.write(to: gitIgnoreURL, atomically: true, encoding: .utf8)
                }
                
                // After adding to gitignore, we should unstage it if it was staged
                let _ = try await worker.runAction(args: ["rm", "--cached", path], in: url)
                
                clearError()
                statusMessage = L10n("Adicionado ao .gitignore: %@", path)
                refreshRepository(setBusy: true)
            } catch {
                isBusy = false
                handleError(error)
            }
        }
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

    private func resolveStashReference(_ input: String) async -> String? {
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
                return value // Fallback to hash if it fails
            }
        }
        
        return value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? value
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

    private func loadDiff(for file: String) {
        guard let url = repositoryURL else { return }
        
        Task {
            do {
                // Get diff including staged changes
                let diff = try await worker.runAction(args: ["diff", "HEAD", "--", file], in: url)
                currentFileDiff = diff.isEmpty ? L10n("Nenhuma mudanca detectada (ou arquivo novo nao rastreado).") : diff
            } catch {
                currentFileDiff = "Erro ao carregar diff: \(error.localizedDescription)"
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

    func logDebug(_ message: String) {
        print("[DEBUG] \(message)")
        debugLog += "\(message)\n"
        if debugLog.count > 5000 {
            debugLog = String(debugLog.suffix(2000))
        }
    }
}
