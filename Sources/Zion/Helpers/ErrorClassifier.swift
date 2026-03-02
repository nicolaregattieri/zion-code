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
            ("already exists", { _ in L10n("error.git.alreadyExists") }),
            ("not a valid branch name", { _ in L10n("error.git.invalidBranchName") }),

            // Worktree
            ("is already used by worktree at '([^']+)'", { match in L10n("error.git.worktreeInUse", match) }),

            // Lock
            ("Unable to create.*\\.lock", { _ in L10n("error.git.lockFile") }),

            // Push rejection
            ("\\[rejected\\].*non-fast-forward", { _ in L10n("error.git.pushRejected") }),
            ("Updates were rejected because the tip", { _ in L10n("error.git.pushRejected") }),
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
}
