import Foundation

// MARK: - Optimistic Staging Helpers
//
// Mutates `uncommittedChanges` (the single source of truth backing `porcelainStatusEntries`)
// synchronously so SwiftUI reflects changes before the async git command completes.
// All helpers are @MainActor-isolated via the enclosing RepositoryViewModel isolation.

extension RepositoryViewModel {

    // MARK: - Snapshot / Restore

    /// Returns a shallow copy of the current uncommitted-changes lines.
    func snapshotPorcelainEntries() -> [String] {
        uncommittedChanges
    }

    /// Replaces uncommittedChanges with a previously captured snapshot (rollback on failure).
    func restorePorcelainEntries(_ snapshot: [String]) {
        uncommittedChanges = snapshot
    }

    // MARK: - Optimistic Stage

    /// Moves matching entries from unstaged/untracked to staged optimistically.
    /// For each URL: if the line represents an untracked file ("?? path") → replace with "A  path"
    /// (staged add). If the line represents an unstaged modification (" M path") → replace with
    /// "M  path" (index-modified, working-tree clean). Other states are left unchanged.
    func applyOptimisticStage(urls: [URL]) {
        guard !urls.isEmpty else { return }
        let paths = Set(urls.map { $0.lastPathComponent.isEmpty ? $0.path : relativePath(for: $0) })
        uncommittedChanges = uncommittedChanges.map { line in
            guard let entry = Self.parsePorcelainStatusLine(line) else { return line }
            guard paths.contains(entry.path) else { return line }
            if entry.isUntracked {
                // Untracked → staged add
                return "A  \(entry.path)"
            } else if entry.indexStatus == " " && entry.worktreeStatus != " " {
                // Unstaged modification → staged modification, working tree clean
                return "\(entry.worktreeStatus)  \(entry.path)"
            }
            // Already staged or unknown state — leave as-is
            return line
        }
    }

    // MARK: - Optimistic Unstage

    /// Moves matching staged entries back to unstaged.
    /// For each URL: if the index-side is "A" (added) → revert to "?? path" (untracked).
    /// Otherwise → move index status to working-tree side (" M path" or similar).
    func applyOptimisticUnstage(urls: [URL]) {
        guard !urls.isEmpty else { return }
        let paths = Set(urls.map { relativePath(for: $0) })
        uncommittedChanges = uncommittedChanges.map { line in
            guard let entry = Self.parsePorcelainStatusLine(line) else { return line }
            guard paths.contains(entry.path) else { return line }
            guard entry.isStaged else { return line }
            if entry.indexStatus == "A" {
                // Staged new file → back to untracked
                return "?? \(entry.path)"
            } else {
                // Staged modification → move back to working tree
                return " \(entry.indexStatus) \(entry.path)"
            }
        }
    }

    // MARK: - Optimistic Discard

    /// Removes the working-tree side for matching entries.
    /// - If the row has staged changes AND working-tree changes → clear only the working-tree side.
    /// - If the row is untracked → remove the row entirely.
    /// - If the row has only working-tree changes (no staged) → remove the row entirely.
    /// This mirrors the semantics of the real `discardChanges(in:)` which restores the working tree
    /// to the index state (or deletes untracked files via `git clean`).
    func applyOptimisticDiscard(urls: [URL]) {
        guard !urls.isEmpty else { return }
        let paths = Set(urls.map { relativePath(for: $0) })
        uncommittedChanges = uncommittedChanges.compactMap { line in
            guard let entry = Self.parsePorcelainStatusLine(line) else { return line }
            guard paths.contains(entry.path) else { return line }
            if entry.isUntracked {
                // Untracked file will be deleted by git clean — remove row
                return nil
            }
            if entry.isStaged && entry.worktreeStatus != " " {
                // Has both staged and working-tree changes — clear working-tree side only
                return "\(entry.indexStatus)  \(entry.path)"
            }
            // Working-tree-only change — row becomes clean, remove it
            return nil
        }
    }

    // MARK: - Private Helpers

    /// Returns the relative path for a URL with respect to the repository root.
    /// Falls back to the absolute path if no repository URL is set.
    private func relativePath(for url: URL) -> String {
        guard let repoURL = repositoryURL else { return url.path }
        let repoPath = repoURL.path
        let filePath = url.path
        if filePath.hasPrefix(repoPath + "/") {
            return String(filePath.dropFirst(repoPath.count + 1))
        }
        // Already relative or outside the repo — return as-is
        return filePath
    }
}
