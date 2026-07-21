import Foundation

extension RepositoryViewModel {

    // MARK: - Fetch / Pull / Push

    func fetch() { runGitAction(label: "Fetch", args: ["fetch", "--all", "--prune"]) }

    func pull() {
        if currentBranchHasUpstream {
            runGitAction(label: "Pull", args: ["pull", "--ff-only"])
        } else {
            presentPullUpstreamPicker()
        }
    }

    func pullRebase() {
        if currentBranchHasUpstream {
            runGitAction(label: "Pull (rebase)", args: ["pull", "--rebase"])
        } else {
            presentPullUpstreamPicker()
        }
    }

    var currentBranchHasUpstream: Bool {
        let branch = currentBranch.clean
        guard !branch.isEmpty, branch != "-" else { return false }
        return branchInfos.first(where: { !$0.isRemote && $0.name == branch })?.upstream.isEmpty == false
    }

    func presentPullUpstreamPicker() {
        let branch = currentBranch.clean
        let defaultRemote = remotes.first(where: { $0.name == "origin" })?.name ?? remotes.first?.name ?? "origin"
        pullUpstreamPickerRemote = defaultRemote
        pullUpstreamPickerBranch = branch.isEmpty || branch == "-" ? "" : branch
        pullUpstreamPickerSetUpstream = true
        isPullUpstreamPickerVisible = true
    }

    func confirmPullWithUpstream() {
        let remote = pullUpstreamPickerRemote.clean
        let branch = pullUpstreamPickerBranch.clean
        let setUpstream = pullUpstreamPickerSetUpstream
        let localBranch = currentBranch.clean
        guard !remote.isEmpty, !branch.isEmpty else { return }
        isPullUpstreamPickerVisible = false

        if setUpstream, !localBranch.isEmpty, localBranch != "-" {
            runGitAction(
                label: "Pull",
                args: ["pull", "--ff-only", remote, branch],
                onCommandSuccess: { [weak self] in
                    guard let self else { return }
                    self.runGitAction(
                        label: "Set upstream",
                        args: ["branch", "--set-upstream-to=\(remote)/\(branch)", localBranch]
                    )
                }
            )
        } else {
            runGitAction(label: "Pull", args: ["pull", "--ff-only", remote, branch])
        }
    }
    func requestPush() {
        guard let repositoryURL else {
            push()
            return
        }

        pushPreflightTask?.cancel()
        isBusy = true
        pushPreflightTask = Task {
            do {
                try await refreshPushDivergence(in: repositoryURL)
                try Task.checkCancellation()
                isBusy = false

                let behind = behindRemoteCount
                let ahead = aheadRemoteCount
                if behind > 0 && ahead > 0 {
                    pushDivergenceState = .diverged(ahead: ahead, behind: behind)
                    showPushDivergenceWarning = true
                } else if behind > 0 {
                    pushDivergenceState = .behind(behind)
                    showPushDivergenceWarning = true
                } else {
                    pushDivergenceState = .clear
                    push()
                }
            } catch is CancellationError {
                isBusy = false
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    func push() {
        let branch = currentBranch
        let hasUpstream = branchInfos.first(where: { !$0.isRemote && $0.name == branch })?.upstream.isEmpty == false
        if hasUpstream {
            runGitAction(label: "Push", args: ["push"])
        } else if !branch.isEmpty {
            let remote = remotes.first?.name ?? "origin"
            runGitAction(label: "Push", args: ["push", "--set-upstream", remote, branch])
        } else {
            runGitAction(label: "Push", args: ["push"])
        }
    }

    func forceWithLeasePush() {
        let branch = currentBranch
        let hasUpstream = branchInfos.first(where: { !$0.isRemote && $0.name == branch })?.upstream.isEmpty == false
        if hasUpstream {
            runGitAction(label: "Push", args: ["push", "--force-with-lease"])
        } else if !branch.isEmpty {
            let remote = remotes.first?.name ?? "origin"
            runGitAction(label: "Push", args: ["push", "--force-with-lease", "--set-upstream", remote, branch])
        } else {
            runGitAction(label: "Push", args: ["push", "--force-with-lease"])
        }
    }


    // MARK: - Auth Error Detection

    func detectAuthError(from errorMessage: String) -> String? {
        let patterns = [
            "Permission denied",
            "Could not read from remote",
            "Authentication failed",
            "fatal: repository.*not found",
            "ERROR: Repository not found",
            "Host key verification failed"
        ]
        for pattern in patterns {
            if errorMessage.range(of: pattern, options: .regularExpression) != nil {
                return errorMessage
            }
        }
        return nil
    }
}
