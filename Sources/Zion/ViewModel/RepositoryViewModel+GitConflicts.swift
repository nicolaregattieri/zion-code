import Foundation

extension RepositoryViewModel {

    // MARK: - Conflict Resolution

    func loadConflictedFiles() {
        guard let repositoryURL else { return }
        conflictTask?.cancel()
        conflictTask = Task {
            do {
                let files = try await worker.listConflictedFiles(in: repositoryURL)
                try Task.checkCancellation()
                conflictedFiles = files
                if let first = files.first(where: { !$0.isResolved }) {
                    selectConflictFile(first.path)
                }
            } catch is CancellationError {
                return
            } catch {
                handleError(error)
            }
        }
    }

    func selectConflictFile(_ path: String) {
        guard let repositoryURL else { return }
        selectedConflictFile = path
        conflictTask?.cancel()
        conflictTask = Task {
            do {
                let content = try await worker.readConflictFileContent(path: path, in: repositoryURL)
                try Task.checkCancellation()
                conflictBlocks = Self.parseConflictBlocks(content)
            } catch is CancellationError {
                return
            } catch {
                handleError(error)
            }
        }
    }

    func resolveRegion(_ regionID: UUID, choice: ConflictChoice) {
        for i in conflictBlocks.indices {
            if case .conflict(var region) = conflictBlocks[i], region.id == regionID {
                region.choice = choice
                conflictBlocks[i] = .conflict(region)
                break
            }
        }
    }

    func saveAndMarkResolved(_ path: String) {
        guard let repositoryURL else { return }
        let merged = buildMergedContent()
        conflictTask?.cancel()
        conflictTask = Task {
            do {
                try await worker.writeResolvedFile(path: path, content: merged, in: repositoryURL)
                try await worker.markFileResolved(path: path, in: repositoryURL)
                try Task.checkCancellation()
                if let idx = conflictedFiles.firstIndex(where: { $0.path == path }) {
                    conflictedFiles[idx].isResolved = true
                }
                statusMessage = "\(path) " + L10n("Marcar como Resolvido")
                // Select next unresolved file
                if let next = conflictedFiles.first(where: { !$0.isResolved }) {
                    selectConflictFile(next.path)
                } else {
                    selectedConflictFile = nil
                    conflictBlocks = []
                }
            } catch is CancellationError {
                return
            } catch {
                handleError(error)
            }
        }
    }

    func continueAfterResolution() {
        guard let repositoryURL else { return }
        isBusy = true
        conflictTask?.cancel()
        conflictTask = Task {
            do {
                let output = try await worker.continueOperation(in: repositoryURL)
                try Task.checkCancellation()
                isConflictViewVisible = false
                statusMessage = output.isEmpty ? L10n("Todos os conflitos resolvidos!") : String(output.prefix(240))
                refreshRepository(setBusy: true)
            } catch is CancellationError {
                return
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    var allConflictsResolved: Bool {
        !conflictedFiles.isEmpty && conflictedFiles.allSatisfy(\.isResolved)
    }

    var unresolvedConflictCount: Int {
        conflictedFiles.filter { !$0.isResolved }.count
    }

    var currentFileAllRegionsChosen: Bool {
        conflictBlocks.allSatisfy { block in
            if case .conflict(let region) = block { return region.choice != .undecided }
            return true
        }
    }

    var activeOperationLabel: String {
        if isMerging { return "Merge" }
        if isRebasing { return "Rebase" }
        if isCherryPicking { return "Cherry-pick" }
        return ""
    }

    func buildMergedContent() -> String {
        var lines: [String] = []
        for block in conflictBlocks {
            switch block {
            case .context(let contextLines):
                lines.append(contentsOf: contextLines)
            case .conflict(let region):
                switch region.choice {
                case .undecided:
                    // Keep original markers if undecided
                    lines.append("<<<<<<< \(region.oursLabel)")
                    lines.append(contentsOf: region.oursLines)
                    lines.append("=======")
                    lines.append(contentsOf: region.theirsLines)
                    lines.append(">>>>>>> \(region.theirsLabel)")
                case .ours:
                    lines.append(contentsOf: region.oursLines)
                case .theirs:
                    lines.append(contentsOf: region.theirsLines)
                case .both:
                    lines.append(contentsOf: region.oursLines)
                    lines.append(contentsOf: region.theirsLines)
                case .bothReverse:
                    lines.append(contentsOf: region.theirsLines)
                    lines.append(contentsOf: region.oursLines)
                case .custom(let text):
                    lines.append(contentsOf: text.components(separatedBy: "\n"))
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    static func parseConflictBlocks(_ content: String) -> [ConflictBlock] {
        let lines = content.components(separatedBy: "\n")
        var blocks: [ConflictBlock] = []
        var contextBuffer: [String] = []
        var oursBuffer: [String] = []
        var theirsBuffer: [String] = []
        var oursLabel = ""
        var theirsLabel = ""
        var inOurs = false
        var inTheirs = false

        for line in lines {
            if line.hasPrefix("<<<<<<< ") {
                if !contextBuffer.isEmpty {
                    blocks.append(.context(contextBuffer))
                    contextBuffer = []
                }
                oursLabel = String(line.dropFirst(8))
                oursBuffer = []
                inOurs = true
                inTheirs = false
            } else if line == "=======" && inOurs {
                inOurs = false
                inTheirs = true
                theirsBuffer = []
            } else if line.hasPrefix(">>>>>>> ") && inTheirs {
                theirsLabel = String(line.dropFirst(8))
                let region = ConflictRegion(
                    oursLines: oursBuffer,
                    theirsLines: theirsBuffer,
                    oursLabel: oursLabel,
                    theirsLabel: theirsLabel
                )
                blocks.append(.conflict(region))
                inTheirs = false
                oursBuffer = []
                theirsBuffer = []
            } else if inOurs {
                oursBuffer.append(line)
            } else if inTheirs {
                theirsBuffer.append(line)
            } else {
                contextBuffer.append(line)
            }
        }
        if !contextBuffer.isEmpty {
            blocks.append(.context(contextBuffer))
        }
        return blocks
    }

    // MARK: - Hunk & Line Staging

    func stageHunk(_ hunk: DiffHunk, file: String) {
        guard let url = repositoryURL else { return }

        // Hunk-level staging doesn't work for untracked files — fall back to full stage
        if statusForFile(file) == "??" {
            stageFile(file)
            return
        }

        let patch = buildPatch(file: file, hunks: [hunk])

        actionTask?.cancel()
        isBusy = true
        actionTask = Task {
            do {
                let _ = try await worker.runActionWithStdin(
                    args: ["apply", "--cached", "--unidiff-zero"],
                    stdin: patch,
                    in: url
                )
                clearError()
                statusMessage = L10n("Hunk staged com sucesso.")
                refreshRepository(setBusy: true)
                if let file = selectedChangeFile { loadDiff(for: file) }
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    func unstageHunk(_ hunk: DiffHunk, file: String) {
        guard let url = repositoryURL else { return }
        let patch = buildPatch(file: file, hunks: [hunk])

        actionTask?.cancel()
        isBusy = true
        actionTask = Task {
            do {
                let _ = try await worker.runActionWithStdin(
                    args: ["apply", "--cached", "--reverse", "--unidiff-zero"],
                    stdin: patch,
                    in: url
                )
                clearError()
                statusMessage = L10n("Hunk unstaged com sucesso.")
                refreshRepository(setBusy: true)
                if let file = selectedChangeFile { loadDiff(for: file) }
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    func stageSelectedLines(from hunk: DiffHunk, selectedLineIDs: Set<UUID>, file: String) {
        guard let url = repositoryURL else { return }
        let patch = buildPartialPatch(file: file, hunk: hunk, selectedLineIDs: selectedLineIDs)
        guard !patch.isEmpty else { return }

        actionTask?.cancel()
        isBusy = true
        actionTask = Task {
            do {
                let _ = try await worker.runActionWithStdin(
                    args: ["apply", "--cached", "--unidiff-zero"],
                    stdin: patch,
                    in: url
                )
                clearError()
                statusMessage = L10n("Linhas staged com sucesso.")
                refreshRepository(setBusy: true)
                if let file = selectedChangeFile { loadDiff(for: file) }
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    func buildPatch(file: String, hunks: [DiffHunk]) -> String {
        var parts: [String] = ["--- a/\(file)", "+++ b/\(file)"]
        for hunk in hunks {
            parts.append(hunk.header)
            for line in hunk.lines {
                switch line.type {
                case .context: parts.append(" \(line.content)")
                case .addition: parts.append("+\(line.content)")
                case .deletion: parts.append("-\(line.content)")
                }
            }
        }
        return parts.joined(separator: "\n") + "\n"
    }

    func buildPartialPatch(file: String, hunk: DiffHunk, selectedLineIDs: Set<UUID>) -> String {
        // Build a hunk with only the selected changed lines; unselected changes become context
        var newLines: [DiffLine] = []
        var oldLineCount = 0
        var newLineCount = 0

        for line in hunk.lines {
            let isSelected = selectedLineIDs.contains(line.id)
            switch line.type {
            case .context:
                newLines.append(line)
                oldLineCount += 1
                newLineCount += 1
            case .addition:
                if isSelected {
                    newLines.append(line)
                    newLineCount += 1
                }
                // If not selected, skip the addition entirely
            case .deletion:
                if isSelected {
                    newLines.append(line)
                    oldLineCount += 1
                } else {
                    // Unselected deletion becomes context
                    newLines.append(DiffLine(type: .context, content: line.content,
                                             oldLineNumber: line.oldLineNumber, newLineNumber: nil))
                    oldLineCount += 1
                    newLineCount += 1
                }
            }
        }

        guard newLines.contains(where: { $0.type != .context }) else { return "" }

        let header = "@@ -\(hunk.oldStart),\(oldLineCount) +\(hunk.newStart),\(newLineCount) @@"
        var parts: [String] = ["--- a/\(file)", "+++ b/\(file)", header]
        for line in newLines {
            switch line.type {
            case .context: parts.append(" \(line.content)")
            case .addition: parts.append("+\(line.content)")
            case .deletion: parts.append("-\(line.content)")
            }
        }
        return parts.joined(separator: "\n") + "\n"
    }
}
