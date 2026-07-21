import Foundation

// MARK: - Auto-Reveal (Wave 3)
//
// When the active editor file changes, expand the parent chain in the file
// tree so the selected file is visible. Mirrors VS Code's `selectActiveFile`
// behavior in `explorerView.ts` — with two guards per the known-bugs rule:
// (1) @AppStorage is avoided inside @Observable, so the persisted flag is a
//     computed property backed by UserDefaults;
// (2) the reveal is a merge into expandedPaths (never a replace), so the
//     Wave 1 snapshot-restore flow is not contradicted.

extension RepositoryViewModel {

    /// Persisted flag for auto-reveal-on-editor-change. Defaults to true.
    /// Stored in `UserDefaults` under the key `code.autoReveal`.
    var autoRevealEnabled: Bool {
        get {
            // Default `true` — first read on a fresh install returns true because
            // `object(forKey:)` is nil, and we treat nil as enabled.
            if UserDefaults.standard.object(forKey: "code.autoReveal") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "code.autoReveal")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "code.autoReveal")
        }
    }

    /// Expands the parent chain of the currently selected code file in the tree.
    /// Safe to call any time — no-ops when disabled, nil, outside the repo, or
    /// when `repositoryURL` is not set.
    func revealSelectedCodeFileInTree() {
        guard autoRevealEnabled else { return }
        guard let file = selectedCodeFile else {
            lastRevealedFileID = nil
            return
        }
        // Skip when the file didn't actually change. Refresh cycles reassign
        // `selectedCodeFile` to a fresh FileItem instance for the same file,
        // which fires `didSet` and would otherwise re-insert every ancestor
        // into `expandedPaths` — reopening folders the user just collapsed
        // (e.g. `.build/…` popping back open on every watcher tick).
        if lastRevealedFileID == file.id { return }
        lastRevealedFileID = file.id
        guard let repoURL = repositoryURL else { return }

        let filePath = file.url.standardizedFileURL.path
        let repoPath = repoURL.standardizedFileURL.path
        guard filePath.hasPrefix(repoPath + "/") else { return }

        // Walk up from the file's parent to the repo root, collecting ancestors.
        var ancestors: [String] = []
        var cursor = file.url.standardizedFileURL.deletingLastPathComponent()
        let rootPath = repoPath
        while cursor.path.hasPrefix(rootPath) && cursor.path != rootPath {
            ancestors.append(cursor.path)
            let parent = cursor.deletingLastPathComponent()
            if parent.path == cursor.path { break } // safety
            cursor = parent
        }

        guard !ancestors.isEmpty else { return }

        // Merge into expandedPaths. expandedPaths is already the source of truth
        // backing the file tree UI — inserting paths expands them.
        var updated = expandedPaths
        for ancestor in ancestors {
            updated.insert(ancestor)
        }
        expandedPaths = updated
    }
}
