import Foundation

/// Maps common Git stderr patterns to user-friendly messages.
enum ErrorClassifier {
    /// Returns a human-readable message for a Git error, or nil if no match.
    static func classify(_ stderr: String) -> String? {
        let patterns: [(regex: String, message: (String) -> String)] = [
            // Authentication
            ("fatal: Authentication failed", { _ in L10n("error.git.authFailed") }),
            ("Permission denied \\(publickey\\)", { _ in L10n("error.git.sshDenied") }),

            // Network
            ("Could not resolve host", { _ in L10n("error.git.noHost") }),
            ("fatal: unable to access", { _ in L10n("error.git.networkError") }),

            // Merge / rebase conflicts
            ("CONFLICT \\(content\\)", { _ in L10n("error.git.mergeConflict") }),
            ("fix conflicts and then", { _ in L10n("error.git.mergeConflict") }),

            // Uncommitted changes
            ("error: Your local changes.*would be overwritten", { _ in L10n("error.git.uncommittedChanges") }),
            ("Please commit your changes or stash them", { _ in L10n("error.git.uncommittedChanges") }),

            // Branch / ref issues
            ("fatal:.*already exists|A branch named.*already exists|A tag named.*already exists", { _ in L10n("error.git.alreadyExists") }),
            ("not a valid branch name", { _ in L10n("error.git.invalidBranchName") }),

            // Worktree
            ("is already used by worktree at '([^']+)'", { match in L10n("error.git.worktreeInUse", match) }),

            // Lock
            ("Unable to create.*\\.lock", { _ in L10n("error.git.lockFile") }),

            // Push rejection
            ("\\[rejected\\].*non-fast-forward", { _ in L10n("error.git.pushRejected") }),
            ("Updates were rejected because the tip", { _ in L10n("error.git.pushRejected") }),

            // Rebase
            ("rebase in progress", { _ in L10n("error.git.rebaseInProgress") }),
            ("No changes - did you forget", { _ in L10n("error.git.rebaseContinueNoChanges") }),

            // Cherry-pick
            ("cherry-pick is not possible|cannot cherry-pick", { _ in L10n("error.git.cherryPickFailed") }),

            // Detached HEAD
            ("HEAD detached|You are in 'detached HEAD' state", { _ in L10n("error.git.detachedHead") }),

            // Diverged branches
            ("have diverged", { _ in L10n("error.git.diverged") }),

            // Submodule
            ("Submodule.*failed|submodule.*not initialized", { _ in L10n("error.git.submoduleError") }),

            // Empty commit
            ("nothing to commit", { _ in L10n("error.git.nothingToCommit") }),

            // Remote not found
            ("fatal: '.*' does not appear to be a git repository", { _ in L10n("error.git.remoteNotFound") }),
        ]

        for (pattern, message) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: stderr, range: NSRange(stderr.startIndex..., in: stderr)) {
                // Extract first capture group if available
                let captured: String
                if match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: stderr) {
                    captured = String(stderr[range])
                } else {
                    captured = ""
                }
                return message(captured)
            }
        }
        return nil
    }

    /// Like `classify`, but always returns a message. Falls back to the first sentence of stderr.
    static func classifyOrFallback(_ stderr: String) -> String {
        if let classified = classify(stderr) {
            return classified
        }
        let firstSentence = stderr.prefix(120).components(separatedBy: CharacterSet(charactersIn: ".\n")).first ?? ""
        return firstSentence.trimmingCharacters(in: .whitespacesAndNewlines) + ". " + L10n("error.git.seeLog")
    }
}
