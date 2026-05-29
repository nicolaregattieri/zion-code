import Foundation

extension RepositoryWorker {

    nonisolated func worktreeList(in repositoryURL: URL, includeStatus: Bool) throws -> [WorktreeItem] {
        let output = try git.run(args: ["worktree", "list", "--porcelain"], in: repositoryURL).stdout
        let currentPath = repositoryURL.path
        let parsed = parseWorktrees(from: output, currentPath: currentPath)
        guard includeStatus else { return parsed }
        return parsed.map { enrichWorktreeStatus(for: $0, repositoryURL: repositoryURL) }
    }

    nonisolated func parseWorktrees(from output: String, currentPath: String) -> [WorktreeItem] {
        var items: [WorktreeItem] = []
        var path = ""
        var head = ""
        var branch = ""
        var isDetached = false
        var isLocked = false
        var lockReason = ""
        var isPrunable = false
        var pruneReason = ""

        func flush() {
            guard !path.isEmpty else { return }
            let normalizedBranch = branch
                .replacingOccurrences(of: "refs/heads/", with: "")
                .replacingOccurrences(of: "refs/remotes/", with: "")
            let isCurrent = URL(fileURLWithPath: path).standardized.path == URL(fileURLWithPath: currentPath).standardized.path
            items.append(
                WorktreeItem(
                    path: path,
                    head: String(head.prefix(8)),
                    branch: normalizedBranch.isEmpty ? "detached" : normalizedBranch,
                    isMainWorktree: isMainWorktreePath(path),
                    isDetached: isDetached,
                    isLocked: isLocked,
                    lockReason: lockReason,
                    isPrunable: isPrunable,
                    pruneReason: pruneReason,
                    isCurrent: isCurrent
                )
            )
            path = ""
            head = ""
            branch = ""
            isDetached = false
            isLocked = false
            lockReason = ""
            isPrunable = false
            pruneReason = ""
        }

        for line in output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) + [""] {
            if line.isEmpty {
                flush()
                continue
            }

            if line.hasPrefix("worktree ") {
                flush()
                path = String(line.dropFirst("worktree ".count))
            } else if line.hasPrefix("HEAD ") {
                head = String(line.dropFirst("HEAD ".count))
            } else if line.hasPrefix("branch ") {
                branch = String(line.dropFirst("branch ".count))
            } else if line.hasPrefix("locked") {
                isLocked = true
                lockReason = String(line.dropFirst("locked".count)).clean
            } else if line.hasPrefix("prunable") {
                isPrunable = true
                pruneReason = String(line.dropFirst("prunable".count)).clean
            } else if line == "detached" {
                isDetached = true
            }
        }

        return items
    }

    nonisolated func isMainWorktreePath(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let gitPath = URL(fileURLWithPath: path).appendingPathComponent(".git").path
        let exists = FileManager.default.fileExists(atPath: gitPath, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    nonisolated func enrichWorktreeStatus(for item: WorktreeItem, repositoryURL: URL) -> WorktreeItem {
        let statusResult = try? git.runAllowingFailure(
            args: ["-C", item.path, "status", "--porcelain"],
            in: repositoryURL
        )
        let uncommittedCount = statusResult?.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .count ?? 0

        let conflictResult = try? git.runAllowingFailure(
            args: ["-C", item.path, "ls-files", "--unmerged"],
            in: repositoryURL
        )
        let hasConflicts = !(conflictResult?.stdout.clean.isEmpty ?? true)

        return WorktreeItem(
            path: item.path,
            head: item.head,
            branch: item.branch,
            isMainWorktree: item.isMainWorktree,
            isDetached: item.isDetached,
            isLocked: item.isLocked,
            lockReason: item.lockReason,
            isPrunable: item.isPrunable,
            pruneReason: item.pruneReason,
            isCurrent: item.isCurrent,
            uncommittedCount: uncommittedCount,
            hasConflicts: hasConflicts
        )
    }
}
