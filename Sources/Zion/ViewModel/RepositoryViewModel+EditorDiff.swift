import Foundation

extension RepositoryViewModel {
    /// Triggered by `activateFileInEditor` and by status refresh. Loads
    /// `git diff HEAD -- <file>` for the currently open editor file and
    /// derives a per-line change map for the gutter ruler.
    ///
    /// Untracked files take a cheaper path: every non-empty line becomes
    /// `.added`, so brand-new files still show the green bar instead of
    /// being silently invisible.
    func loadEditorDiffMarkers(for fileURL: URL?) {
        editorDiffMarkersTask?.cancel()
        editorDiffMarkersTask = nil
        guard let fileURL, let repoURL = repositoryURL else {
            clearEditorDiffMarkers()
            return
        }
        let repoPath = repoURL.path.hasSuffix("/") ? repoURL.path : repoURL.path + "/"
        let absolute = fileURL.path
        guard absolute.hasPrefix(repoPath) else {
            clearEditorDiffMarkers()
            return
        }
        let relativePath = String(absolute.dropFirst(repoPath.count))
        editorDiffMarkersPath = relativePath

        let kind = uncommittedKindByPath[relativePath]
        // Snapshot the current kind so `rebuildUncommittedLookupSets` can
        // detect when an external write flips it (e.g. LLM agent saves a
        // brand-new untracked file → modified, or user `git reset`s and the
        // file goes clean).
        editorDiffMarkersLastKind = kind
        if kind == nil {
            clearEditorDiffMarkers(keepingPath: true)
            return
        }

        if kind == .untracked {
            // For brand-new files git diff returns nothing useful; mark every
            // line as added so the user still sees the green change bar.
            applyUntrackedMarkers(for: fileURL, relativePath: relativePath)
            return
        }

        editorDiffMarkersTask = Task { [weak self, relativePath, repoURL] in
            guard let self else { return }
            do {
                let diff = try await worker.runAction(
                    args: ["diff", "HEAD", "--", relativePath],
                    in: repoURL
                )
                if Task.isCancelled { return }
                let hunks = Self.parseDiffHunks(diff)
                let result = Self.buildEditorDiffMarkers(from: hunks)
                guard self.editorDiffMarkersPath == relativePath else { return }
                self.editorDiffMarkers = result.markers
                self.editorDiffOriginalByLine = result.originalByLine
                self.editorDiffMarkersVersion &+= 1
            } catch is CancellationError {
                return
            } catch {
                logger.log(.warn, "Editor diff markers load failed: \(error.localizedDescription)", context: relativePath, source: #function)
            }
        }
    }

    /// Called from `rebuildUncommittedLookupSets()` so user edits + saves
    /// keep the gutter bars in sync without forcing a manual reopen.
    func refreshEditorDiffMarkersIfNeeded() {
        guard let fileURL = selectedCodeFile?.url else { return }
        loadEditorDiffMarkers(for: fileURL)
    }

    private func clearEditorDiffMarkers(keepingPath: Bool = false) {
        if !editorDiffMarkers.isEmpty || !editorDiffOriginalByLine.isEmpty {
            editorDiffMarkers = [:]
            editorDiffOriginalByLine = [:]
            editorDiffMarkersVersion &+= 1
        }
        if !keepingPath {
            editorDiffMarkersPath = nil
        }
    }

    private func applyUntrackedMarkers(for fileURL: URL, relativePath: String) {
        editorDiffMarkersTask = Task { [weak self, fileURL, relativePath] in
            guard let self else { return }
            let content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            if Task.isCancelled { return }
            guard self.editorDiffMarkersPath == relativePath else { return }
            var markers: [Int: EditorLineChangeKind] = [:]
            let lineCount = content.isEmpty ? 0 : content.split(separator: "\n", omittingEmptySubsequences: false).count
            for line in 1...max(1, lineCount) {
                markers[line] = .added
            }
            self.editorDiffMarkers = markers
            self.editorDiffOriginalByLine = [:]
            self.editorDiffMarkersVersion &+= 1
        }
    }

    /// Walks parsed hunks and produces a `lineNumber -> kind` map keyed by
    /// new-side (working tree) line numbers.
    ///
    /// Rules:
    /// - A pure addition (no preceding deletion in the same block) → `.added`
    /// - An addition that consumes a pending deletion → `.modified`
    /// - Deletions left unmatched at the end of a hunk → `.deleted` painted
    ///   on the line *immediately above* the gap (the closest visible line
    ///   the user can still scroll to). At top-of-file we fall back to line 1
    ///   so the marker remains visible.
    static func buildEditorDiffMarkers(from hunks: [DiffHunk]) -> (markers: [Int: EditorLineChangeKind], originalByLine: [Int: [String]]) {
        var markers: [Int: EditorLineChangeKind] = [:]
        var original: [Int: [String]] = [:]
        for hunk in hunks {
            var pendingDeletionContent: [String] = []
            var newCursor = hunk.newStart
            for line in hunk.lines {
                switch line.type {
                case .context:
                    if !pendingDeletionContent.isEmpty {
                        let target = max(1, newCursor - 1)
                        if markers[target] == nil {
                            markers[target] = .deleted
                            original[target, default: []].append(contentsOf: pendingDeletionContent)
                        }
                        pendingDeletionContent.removeAll()
                    }
                    newCursor += 1
                case .deletion:
                    pendingDeletionContent.append(line.content)
                case .addition:
                    if !pendingDeletionContent.isEmpty {
                        markers[newCursor] = .modified
                        original[newCursor, default: []].append(pendingDeletionContent.removeFirst())
                    } else {
                        markers[newCursor] = .added
                    }
                    newCursor += 1
                }
            }
            if !pendingDeletionContent.isEmpty {
                let target = max(1, newCursor - 1)
                if markers[target] == nil {
                    markers[target] = .deleted
                }
                original[target, default: []].append(contentsOf: pendingDeletionContent)
            }
        }
        return (markers, original)
    }
}
