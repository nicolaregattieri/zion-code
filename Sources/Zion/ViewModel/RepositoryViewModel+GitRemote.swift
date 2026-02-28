import Foundation

extension RepositoryViewModel {

    // MARK: - Fetch / Pull / Push

    func fetch() { runGitAction(label: "Fetch", args: ["fetch", "--all", "--prune"]) }
    func pull() { runGitAction(label: "Pull", args: ["pull", "--ff-only"]) }
    func pullRebase() { runGitAction(label: "Pull (rebase)", args: ["pull", "--rebase"]) }
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
