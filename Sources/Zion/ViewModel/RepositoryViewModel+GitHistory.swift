import Foundation

extension RepositoryViewModel {

    // MARK: - Commit Details

    func loadCommitDetails(for commitID: String?, policy: CommitDetailsLoadPolicy = .interactive) {
        guard let repositoryURL else {
            commitDetails = L10n("Selecione um repositorio Git.")
            return
        }

        guard let commitID else {
            commitDetails = L10n("Selecione um commit para ver os detalhes.")
            return
        }

        detailsTask?.cancel()
        let requestID = UUID()
        detailsRequestID = requestID
        switch policy {
        case .interactive:
            commitDetails = L10n("Carregando detalhes do commit...")
        case .silent:
            break
        }

        detailsTask = Task {
            do {
                let details = try await worker.loadCommitDetails(in: repositoryURL, commitID: commitID)
                try Task.checkCancellation()
                guard detailsRequestID == requestID else { return }
                if commitDetails != details {
                    commitDetails = details
                }
            } catch is CancellationError {
                return
            } catch {
                guard detailsRequestID == requestID else { return }
                logger.log(.warn, "Failed to load commit details: \(error.localizedDescription)", context: commitID, source: #function)
                let message = error.localizedDescription
                if commitDetails != message {
                    commitDetails = message
                }
            }
        }
    }

    // MARK: - Diff Loading

    func statusForFile(_ file: String) -> String? {
        uncommittedChanges.first { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 4 else { return false }
            let start = trimmed.index(trimmed.startIndex, offsetBy: 3)
            var path = String(trimmed[start...]).trimmingCharacters(in: .whitespaces)
            if let arrowRange = path.range(of: " -> ") {
                path = String(path[arrowRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
            return path == file
        }.map { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return String(trimmed.prefix(2))
        }
    }

    static func buildSyntheticNewFileDiff(file: String, lines: [String]) -> String {
        let count = lines.count
        var result = "diff --git a/\(file) b/\(file)\n"
        result += "new file mode 100644\n"
        result += "--- /dev/null\n"
        result += "+++ b/\(file)\n"
        result += "@@ -0,0 +1,\(count) @@\n"
        for line in lines {
            result += "+\(line)\n"
        }
        return result
    }

    func loadDiff(for file: String) {
        guard let url = repositoryURL else { return }

        Task {
            do {
                // Get diff including staged changes
                let diff = try await worker.runAction(args: ["diff", "HEAD", "--", file], in: url)
                let newDiff: String
                let newHunks: [DiffHunk]
                if diff.isEmpty {
                    let status = statusForFile(file)
                    let resolvedDiff: String? = await resolveMissingDiff(for: file, status: status, in: url)
                    if let resolvedDiff, !resolvedDiff.isEmpty {
                        newDiff = resolvedDiff
                        newHunks = Self.parseDiffHunks(resolvedDiff)
                    } else {
                        newDiff = L10n("Nenhuma mudanca detectada (ou arquivo novo nao rastreado).")
                        newHunks = []
                    }
                } else {
                    newDiff = diff
                    newHunks = Self.parseDiffHunks(diff)
                }
                // Only update UI when the diff content actually changed,
                // preventing flicker and preserving hunk selection on auto-refresh.
                if newDiff != currentFileDiff {
                    currentFileDiff = newDiff
                    currentFileDiffHunks = newHunks
                    selectedHunkLines = []
                }
            } catch {
                logger.log(.warn, "Failed to load diff: \(error.localizedDescription)", context: file, source: #function)
                currentFileDiff = L10n("error.loadDiff", error.localizedDescription)
                currentFileDiffHunks = []
            }
        }
    }

    func resolveMissingDiff(for file: String, status: String?, in url: URL) async -> String? {
        if status == "??" {
            return await resolveUntrackedDiff(for: file, in: url)
        } else if status?.hasPrefix("A") == true {
            return await resolveStagedNewFileDiff(for: file, in: url)
        }
        return nil
    }

    func resolveUntrackedDiff(for file: String, in url: URL) async -> String? {
        let fullPath = url.appendingPathComponent(file).path
        let fm = FileManager.default
        var isDir: ObjCBool = false

        // Directory: list contents as synthetic diff
        if fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
            if let entries = try? fm.contentsOfDirectory(atPath: fullPath) {
                let lines = entries.sorted().map { "  \($0)" }
                return Self.buildSyntheticNewFileDiff(file: file, lines: ["[\(file)]"] + lines)
            }
            return nil
        }

        // Try git diff --no-index (exits 1 on success for new files)
        if let result = try? await worker.runActionAllowingFailure(
            args: ["diff", "--no-index", "--", "/dev/null", file],
            in: url
        ), result.status == 1, !result.output.isEmpty {
            return result.output
        }

        // Fallback: read file directly
        return readFileAsSyntheticDiff(file: file, fullPath: fullPath)
    }

    func resolveStagedNewFileDiff(for file: String, in url: URL) async -> String? {
        // Try git diff --cached for staged new files
        if let diff = try? await worker.runAction(args: ["diff", "--cached", "--", file], in: url),
           !diff.isEmpty {
            return diff
        }

        // Fallback: git show :<file> (index version)
        if let content = try? await worker.runAction(args: ["show", ":\(file)"], in: url),
           !content.isEmpty {
            let lines = content.components(separatedBy: "\n")
            return Self.buildSyntheticNewFileDiff(file: file, lines: lines)
        }

        return nil
    }

    func readFileAsSyntheticDiff(file: String, fullPath: String) -> String? {
        guard let data = FileManager.default.contents(atPath: fullPath) else { return nil }
        // Check for binary content
        if data.contains(0) {
            return L10n("Arquivo binario ou nao legivel.")
        }
        guard let content = String(data: data, encoding: .utf8), !content.isEmpty else { return nil }
        let lines = content.components(separatedBy: "\n")
        return Self.buildSyntheticNewFileDiff(file: file, lines: lines)
    }

    // MARK: - Commit Stats

    /// Carry over cached insertions/deletions from the existing commits array
    /// so stats don't blink away between refresh and async stats reload.
    func mergeExistingStats(into newCommits: [Commit]) -> [Commit] {
        guard !commits.isEmpty else { return newCommits }
        var cache: [String: (Int, Int)] = [:]
        for c in commits {
            if let ins = c.insertions, let del = c.deletions {
                cache[c.id] = (ins, del)
            }
        }
        guard !cache.isEmpty else { return newCommits }
        var merged = newCommits
        for i in merged.indices {
            if let cached = cache[merged[i].id] {
                merged[i].insertions = cached.0
                merged[i].deletions = cached.1
            }
        }
        return merged
    }

    func loadCommitStats() {
        guard let url = repositoryURL, !commits.isEmpty else { return }
        commitStatsTask?.cancel()
        let hashes = commits.map(\.id)
        commitStatsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stats = try await worker.fetchCommitStats(in: url, hashes: hashes)
                try Task.checkCancellation()
                // Build updated array in one pass to trigger a single observation notification
                var updated = commits
                for i in updated.indices {
                    if let stat = stats[updated[i].id] {
                        updated[i].insertions = stat.0
                        updated[i].deletions = stat.1
                    }
                }
                commits = updated
            } catch {
                // Silently fail — stats are optional enhancement
            }
        }
    }

    // MARK: - Diff Parsing

    static func parseDiffHunks(_ rawDiff: String) -> [DiffHunk] {
        let lines = rawDiff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var hunks: [DiffHunk] = []
        var i = 0

        // Skip file header lines (diff --git, index, ---, +++)
        while i < lines.count && !lines[i].hasPrefix("@@") {
            i += 1
        }

        while i < lines.count {
            let line = lines[i]
            guard line.hasPrefix("@@") else { i += 1; continue }

            // Parse hunk header: @@ -oldStart,oldCount +newStart,newCount @@
            let header = line
            var oldStart = 0, oldCount = 0, newStart = 0, newCount = 0
            if let rangeMatch = line.range(of: "@@ -(\\d+)(?:,(\\d+))? \\+(\\d+)(?:,(\\d+))? @@",
                                           options: .regularExpression) {
                let headerStr = String(line[rangeMatch])
                let nums = headerStr.matches(of: /(\d+)/)
                if nums.count >= 3 {
                    oldStart = Int(nums[0].output.1) ?? 0
                    if nums.count == 4 {
                        oldCount = Int(nums[1].output.1) ?? 0
                        newStart = Int(nums[2].output.1) ?? 0
                        newCount = Int(nums[3].output.1) ?? 0
                    } else {
                        oldCount = 0
                        newStart = Int(nums[1].output.1) ?? 0
                        newCount = Int(nums[2].output.1) ?? 0
                    }
                }
            }

            i += 1
            var diffLines: [DiffLine] = []
            var currentOld = oldStart
            var currentNew = newStart

            while i < lines.count && !lines[i].hasPrefix("@@") {
                let diffLineText = lines[i]
                if diffLineText.hasPrefix("+") {
                    diffLines.append(DiffLine(type: .addition, content: String(diffLineText.dropFirst()),
                                              oldLineNumber: nil, newLineNumber: currentNew))
                    currentNew += 1
                } else if diffLineText.hasPrefix("-") {
                    diffLines.append(DiffLine(type: .deletion, content: String(diffLineText.dropFirst()),
                                              oldLineNumber: currentOld, newLineNumber: nil))
                    currentOld += 1
                } else if diffLineText.hasPrefix("\\") {
                    // "\ No newline at end of file" — skip
                    i += 1
                    continue
                } else {
                    // Context line (starts with space or is empty)
                    let content = diffLineText.isEmpty ? "" : String(diffLineText.dropFirst())
                    diffLines.append(DiffLine(type: .context, content: content,
                                              oldLineNumber: currentOld, newLineNumber: currentNew))
                    currentOld += 1
                    currentNew += 1
                }
                i += 1
            }

            hunks.append(DiffHunk(header: header, oldStart: oldStart, oldCount: oldCount,
                                  newStart: newStart, newCount: newCount, lines: diffLines))
        }

        return hunks
    }


    // MARK: - Commit Diff for File

    func loadDiffForCommitFile(commitID: String, file: String) {
        guard let url = repositoryURL else { return }
        selectedCommitFile = file
        Task {
            do {
                let diff = try await worker.runAction(
                    args: ["diff", "\(commitID)~1", commitID, "--", file],
                    in: url
                )
                currentCommitFileDiff = diff.isEmpty ? L10n("Nenhuma mudanca.") : diff
                currentCommitFileDiffHunks = Self.parseDiffHunks(diff)
            } catch {
                logger.log(.warn, "Failed to load commit file diff: \(error.localizedDescription)", context: "\(commitID):\(file)", source: #function)
                currentCommitFileDiff = L10n("error.generic", error.localizedDescription)
                currentCommitFileDiffHunks = []
            }
        }
    }

    // MARK: - Git Blame

    func loadBlame(for file: FileItem) {
        guard let url = repositoryURL else { return }
        let filePath: String
        if let repoURL = repositoryURL {
            filePath = file.url.path.replacingOccurrences(of: repoURL.path + "/", with: "")
        } else {
            filePath = file.name
        }

        blameTask?.cancel()
        blameEntries = []

        blameTask = Task {
            do {
                let output = try await worker.runAction(
                    args: ["blame", "--porcelain", filePath],
                    in: url
                )
                let entries = Self.parseBlameOutput(output)
                blameEntries = entries
            } catch {
                logger.log(.warn, "Failed to load blame: \(error.localizedDescription)", context: filePath, source: #function)
                blameEntries = []
                statusMessage = "Blame: \(error.localizedDescription)"
            }
        }
    }

    func toggleBlame() {
        isBlameVisible.toggle()
        if isBlameVisible, let file = selectedCodeFile {
            loadBlame(for: file)
        } else {
            blameEntries = []
        }
    }

    static func parseBlameOutput(_ raw: String) -> [BlameEntry] {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var entries: [BlameEntry] = []
        var i = 0
        var authorMap: [String: String] = [:]
        var dateMap: [String: Date] = [:]

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        while i < lines.count {
            let line = lines[i]
            // Header line: <hash> <orig-line> <final-line> [<num-lines>]
            let parts = line.split(separator: " ")
            guard parts.count >= 3,
                  let hash = parts.first, hash.count >= 7,
                  hash.allSatisfy({ $0.isHexDigit }),
                  let lineNum = Int(parts[2]) else {
                i += 1
                continue
            }

            let commitHash = String(hash)
            i += 1

            // Read metadata lines until we hit the tab-prefixed content line
            var author = authorMap[commitHash] ?? ""
            var date = dateMap[commitHash] ?? Date.distantPast

            while i < lines.count && !lines[i].hasPrefix("\t") {
                let metaLine = lines[i]
                if metaLine.hasPrefix("author ") {
                    author = String(metaLine.dropFirst(7))
                    authorMap[commitHash] = author
                } else if metaLine.hasPrefix("author-time ") {
                    if let ts = TimeInterval(metaLine.dropFirst(12)) {
                        date = Date(timeIntervalSince1970: ts)
                        dateMap[commitHash] = date
                    }
                }
                i += 1
            }

            // Content line (starts with tab)
            var content = ""
            if i < lines.count && lines[i].hasPrefix("\t") {
                content = String(lines[i].dropFirst(1))
            }
            i += 1

            entries.append(BlameEntry(
                commitHash: commitHash,
                shortHash: String(commitHash.prefix(8)),
                author: author,
                date: date,
                lineNumber: lineNum,
                content: content
            ))
        }

        return entries
    }

    // MARK: - Reflog

    func loadReflog() {
        guard let url = repositoryURL else { return }

        reflogTask?.cancel()
        reflogEntries = []

        reflogTask = Task {
            do {
                let output = try await worker.runAction(
                    args: ["reflog", "--format=%H|%h|%gD|%gs|%ci|%cr", "-n", "\(Constants.Limits.reflogEntryLimit)"],
                    in: url
                )
                let entries = Self.parseReflogOutput(output)
                reflogEntries = entries
            } catch {
                logger.log(.warn, "Failed to load reflog: \(error.localizedDescription)", source: #function)
                reflogEntries = []
            }
        }
    }

    func undoLastAction() {
        guard !reflogEntries.isEmpty else { return }
        // Find the previous state (reflog entry at index 1)
        guard reflogEntries.count > 1 else { return }
        let target = reflogEntries[1]
        runGitAction(label: "Undo", args: ["reset", "--soft", target.hash])
    }

    static func parseReflogOutput(_ raw: String) -> [ReflogEntry] {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"

        // First pass: parse raw entries
        struct RawEntry {
            let hash, shortHash, refName, action, message, relDate: String
            let date: Date
        }
        var rawEntries: [RawEntry] = []
        for line in lines {
            let parts = line.split(separator: "|", maxSplits: 5).map(String.init)
            guard parts.count >= 6 else { continue }
            let action = parts[3].split(separator: ":", maxSplits: 1).first.map(String.init) ?? parts[3]
            rawEntries.append(RawEntry(
                hash: parts[0], shortHash: parts[1], refName: parts[2],
                action: action, message: parts[3],
                relDate: parts[5],
                date: dateFormatter.date(from: parts[4]) ?? .distantPast
            ))
        }

        // Second pass: walk entries (newest->oldest) tracking which branch HEAD was on.
        // When we see "checkout: moving from X to Y", entries above were on Y, entries below on X.
        var branchStack = ""
        // Find the first checkout to seed the current branch
        for entry in rawEntries where entry.action.lowercased() == "checkout" {
            if let branches = ReflogEntry.parseCheckoutBranches(from: entry.message) {
                branchStack = branches.to
                break
            }
        }

        var results: [ReflogEntry] = []
        for entry in rawEntries {
            if entry.action.lowercased() == "checkout",
               let branches = ReflogEntry.parseCheckoutBranches(from: entry.message) {
                let detail = ReflogEntry.humanDetail(from: entry.message, action: entry.action)
                results.append(ReflogEntry(
                    hash: entry.hash, shortHash: entry.shortHash, refName: entry.refName,
                    action: entry.action, message: entry.message, detail: detail,
                    branch: branches.to, date: entry.date, relativeDate: entry.relDate
                ))
                branchStack = branches.from
            } else {
                let detail = ReflogEntry.humanDetail(from: entry.message, action: entry.action)
                results.append(ReflogEntry(
                    hash: entry.hash, shortHash: entry.shortHash, refName: entry.refName,
                    action: entry.action, message: entry.message, detail: detail,
                    branch: branchStack, date: entry.date, relativeDate: entry.relDate
                ))
            }
        }
        return results
    }

    // MARK: - Interactive Rebase

    func prepareInteractiveRebase(from baseRef: String) {
        guard let url = repositoryURL else { return }
        rebaseBaseRef = baseRef

        Task {
            do {
                let output = try await worker.runAction(
                    args: ["log", "--oneline", "--reverse", "\(baseRef)..HEAD"],
                    in: url
                )
                let items = output.split(separator: "\n", omittingEmptySubsequences: true).map { line -> RebaseItem in
                    let parts = line.split(separator: " ", maxSplits: 1)
                    let hash = parts.count > 0 ? String(parts[0]) : ""
                    let subject = parts.count > 1 ? String(parts[1]) : ""
                    return RebaseItem(hash: hash, shortHash: String(hash.prefix(8)), subject: subject)
                }
                rebaseItems = items
                isRebaseSheetVisible = true
            } catch {
                handleError(error)
            }
        }
    }

    func executeInteractiveRebase() {
        guard let url = repositoryURL, !rebaseItems.isEmpty else { return }

        // Build the rebase todo list
        let todoList = rebaseItems.map { item in
            "\(item.action.rawValue) \(item.hash) \(item.subject)"
        }.joined(separator: "\n")

        actionTask?.cancel()
        isBusy = true
        isRebaseSheetVisible = false

        actionTask = Task {
            do {
                // Pre-snapshot: protect uncommitted work before interactive rebase
                if uncommittedCount > 0 {
                    let stashHash = try await worker.runAction(args: ["stash", "create"], in: url)
                    let trimmedHash = stashHash.clean
                    if !trimmedHash.isEmpty {
                        let _ = try await worker.runAction(
                            args: ["stash", "store", "-m", "zion-pre-rebase-interactive", trimmedHash],
                            in: url
                        )
                        logger.log(.info, "Pre-snapshot created: zion-pre-rebase-interactive", context: trimmedHash, source: #function)
                    }
                }

                // Use GIT_SEQUENCE_EDITOR to pass the todo list
                // We write the todo to a temp file and use a script that replaces the editor
                let tempDir = ZionTemp.directory
                let todoFile = tempDir.appendingPathComponent("zion-rebase-todo-\(UUID().uuidString)")
                try todoList.write(to: todoFile, atomically: true, encoding: .utf8)

                let scriptContent = "#!/bin/sh\ncp \"$ZION_TODO_FILE\" \"$1\""
                let scriptFile = tempDir.appendingPathComponent("zion-rebase-editor-\(UUID().uuidString).sh")
                try scriptContent.write(to: scriptFile, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptFile.path)

                // Run rebase with our custom sequence editor
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["git", "rebase", "-i", rebaseBaseRef]
                process.currentDirectoryURL = url
                var env = ProcessInfo.processInfo.environment
                env["GIT_SEQUENCE_EDITOR"] = scriptFile.path
                env["ZION_TODO_FILE"] = todoFile.path
                env["LC_ALL"] = "C"
                env["LANG"] = "C"
                process.environment = env

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                try process.run()
                process.waitUntilExit()

                // Cleanup temp files
                try? FileManager.default.removeItem(at: todoFile)
                try? FileManager.default.removeItem(at: scriptFile)

                let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

                if process.terminationStatus != 0 {
                    handleError(GitClientError.commandFailed(
                        command: "git rebase -i \(rebaseBaseRef)",
                        message: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                    isBusy = false
                } else {
                    clearError()
                    statusMessage = L10n("Rebase interativo concluido com sucesso.")
                    refreshRepository(setBusy: true)
                }
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }


    // MARK: - Commit Signing Visualization

    func loadSignatureStatuses() {
        guard let url = repositoryURL else { return }

        Task {
            do {
                let output = try await worker.runAction(
                    args: ["log", "--format=%H %G?", "-n", "100"],
                    in: url
                )
                var statuses: [String: String] = [:]
                for line in output.split(separator: "\n") {
                    let parts = line.split(separator: " ", maxSplits: 1)
                    if parts.count == 2 {
                        statuses[String(parts[0])] = String(parts[1])
                    }
                }
                commitSignatureStatus = statuses
            } catch {
                logger.log(.warn, "Failed to load signature statuses: \(error.localizedDescription)", source: #function)
                commitSignatureStatus = [:]
            }
        }
    }

    func signatureStatusFor(_ commitHash: String) -> String? {
        commitSignatureStatus[commitHash]
    }

    // MARK: - File History

    func loadFileHistory(for relativePath: String) {
        guard let url = repositoryURL else { return }

        fileHistoryTask?.cancel()
        isFileHistoryLoading = true
        fileHistoryEntries = []

        fileHistoryTask = Task {
            defer { isFileHistoryLoading = false }

            do {
                let output = try await worker.runAction(
                    args: ["log", "--follow", "--format=%H|%h|%an|%ar|%s", "-50", "--", relativePath],
                    in: url
                )

                let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
                var entries: [FileHistoryEntry] = []
                for line in lines {
                    let parts = line.components(separatedBy: "|")
                    guard parts.count >= 5 else { continue }
                    entries.append(FileHistoryEntry(
                        hash: parts[0],
                        shortHash: parts[1],
                        author: parts[2],
                        date: parts[3],
                        message: parts[4...].joined(separator: "|")
                    ))
                }
                fileHistoryEntries = entries
                isFileHistoryVisible = true
            } catch {
                logger.log(.error, "File history failed: \(error.localizedDescription)", source: #function)
                lastError = error.localizedDescription
            }
        }
    }

}
