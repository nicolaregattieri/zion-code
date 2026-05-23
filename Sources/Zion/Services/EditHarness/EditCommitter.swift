import Foundation

// MARK: - Input / Output types

struct EditCommitInput: Equatable {
    let path: String
    let contents: String
}

struct EditCommitResult: Equatable {
    var commitSHA: String?
    var snapshotRef: String?
    var failureReason: String?
}

// MARK: - Actor

actor EditCommitter {

    private let worker: RepositoryWorker
    private let commitMessageProvider: @Sendable (String, String) async throws -> String

    init(
        worker: RepositoryWorker,
        commitMessageProvider: @escaping @Sendable (String, String) async throws -> String
    ) {
        self.worker = worker
        self.commitMessageProvider = commitMessageProvider
    }

    // MARK: - Main entry point

    func commit(inputs: [EditCommitInput], in repoURL: URL, branch: String) async -> EditCommitResult {
        guard !inputs.isEmpty else {
            return EditCommitResult(failureReason: "no_inputs")
        }

        var result = EditCommitResult()

        do {
            // Step 1: Snapshot if dirty
            let statusOutput = try await worker.runAction(args: ["status", "--porcelain"], in: repoURL)
            let uncommittedLines = statusOutput
                .split(separator: "\n", omittingEmptySubsequences: true)
                .count
            if uncommittedLines > 0 {
                let shortSHA = String(UUID().uuidString.prefix(8))
                let label = "zion-pre-aiedit-\(shortSHA)"

                // Try stash create first (captures tracked modifications + deletions).
                let hash = try await worker.runAction(args: ["stash", "create"], in: repoURL)
                let trimmedHash = hash.clean
                if !trimmedHash.isEmpty {
                    // Has tracked changes — store the object as a stash entry.
                    try await worker.runAction(
                        args: ["stash", "store", "-m", label, trimmedHash],
                        in: repoURL
                    )
                    result.snapshotRef = label
                } else {
                    // Untracked-only tree: stash create produces nothing.
                    // Use stash push --include-untracked to capture untracked files.
                    let (_, status) = try await worker.runActionAllowingFailure(
                        args: ["stash", "push", "--include-untracked", "-m", label],
                        in: repoURL
                    )
                    if status == 0 {
                        result.snapshotRef = label
                    }
                }
            }

            // Step 2: Write files
            for input in inputs {
                let fileURL = repoURL.appendingPathComponent(input.path)
                let parentDir = fileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(
                    at: parentDir, withIntermediateDirectories: true
                )
                try input.contents.write(to: fileURL, atomically: true, encoding: .utf8)
            }

            // Step 3: git add
            let paths = inputs.map { $0.path }
            try await worker.runAction(args: ["add"] + paths, in: repoURL)

            // Step 4: Check for actual changes
            let diffStat = (try? await worker.runAction(args: ["diff", "--cached", "--stat"], in: repoURL)) ?? ""
            let diff = (try? await worker.runAction(args: ["diff", "--cached"], in: repoURL)) ?? ""

            if diffStat.clean.isEmpty && diff.clean.isEmpty {
                result.failureReason = "no_changes"
                return result
            }

            // Step 5: Generate commit message
            let rawMessage = try await commitMessageProvider(diff, diffStat)
            let message: String
            if rawMessage.hasPrefix("aiedit:") {
                message = rawMessage
            } else {
                message = "aiedit: \(rawMessage)"
            }

            // Step 6: Commit
            try await worker.runAction(args: ["commit", "-m", message], in: repoURL)

            // Step 7: Capture HEAD SHA
            let headSHA = try await worker.runAction(args: ["rev-parse", "HEAD"], in: repoURL)
            result.commitSHA = headSHA.clean

        } catch {
            result.failureReason = error.localizedDescription
        }

        return result
    }
}
