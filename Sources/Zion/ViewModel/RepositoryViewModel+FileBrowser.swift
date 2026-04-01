import Foundation
import SwiftUI

extension RepositoryViewModel {

    func performPreferredUndo() {
        let app = NSApplication.shared
        logger.log(
            .info,
            "replace.undo.request",
            context: "responder=\(debugFirstResponderDescription()) undoStack=\(replaceUndoStack.count) redoStack=\(replaceRedoStack.count)",
            source: #function
        )
        if shouldRouteUndoToResponderChain {
            logger.log(.info, "replace.undo.route responder", context: debugFirstResponderDescription(), source: #function)
            app.sendAction(Selector(("undo:")), to: nil, from: nil)
            return
        }

        if hasPendingWorkspaceReplaceUndo {
            logger.log(.info, "replace.undo.route workspace", context: "undoStack=\(replaceUndoStack.count)", source: #function)
            performWorkspaceReplaceUndo()
            return
        }

        logger.log(.info, "replace.undo.route fallback", context: debugFirstResponderDescription(), source: #function)
        app.sendAction(Selector(("undo:")), to: nil, from: nil)
    }

    func performPreferredRedo() {
        let app = NSApplication.shared
        logger.log(
            .info,
            "replace.redo.request",
            context: "responder=\(debugFirstResponderDescription()) undoStack=\(replaceUndoStack.count) redoStack=\(replaceRedoStack.count)",
            source: #function
        )
        if shouldRouteRedoToResponderChain {
            logger.log(.info, "replace.redo.route responder", context: debugFirstResponderDescription(), source: #function)
            app.sendAction(Selector(("redo:")), to: nil, from: nil)
            return
        }

        if hasPendingWorkspaceReplaceRedo {
            logger.log(.info, "replace.redo.route workspace", context: "redoStack=\(replaceRedoStack.count)", source: #function)
            performWorkspaceReplaceRedo()
            return
        }

        logger.log(.info, "replace.redo.route fallback", context: debugFirstResponderDescription(), source: #function)
        app.sendAction(Selector(("redo:")), to: nil, from: nil)
    }

    private var shouldRouteUndoToResponderChain: Bool {
        guard let responder = NSApplication.shared.keyWindow?.firstResponder as? NSResponder else { return false }
        if responder is NSTextView, !(responder is ZionTextView) {
            return responder.undoManager?.canUndo == true
        }
        return responder is ZionTextView && responder.undoManager?.canUndo == true && !hasPendingWorkspaceReplaceUndo
    }

    private var shouldRouteRedoToResponderChain: Bool {
        guard let responder = NSApplication.shared.keyWindow?.firstResponder as? NSResponder else { return false }
        if responder is NSTextView, !(responder is ZionTextView) {
            return responder.undoManager?.canRedo == true
        }
        return responder is ZionTextView && responder.undoManager?.canRedo == true && !hasPendingWorkspaceReplaceRedo
    }

    // MARK: - Multi-Selection

    func plainClickFile(_ item: FileItem) {
        selectedFileIDs = [item.id]
        lastClickedFileID = item.id
        if item.isDirectory {
            withAnimation(DesignSystem.Motion.snappy) { toggleExpansion(for: item.id) }
        } else {
            selectCodeFile(item)
        }
    }

    func toggleFileSelection(_ item: FileItem) {
        if selectedFileIDs.contains(item.id) {
            selectedFileIDs.remove(item.id)
        } else {
            selectedFileIDs.insert(item.id)
        }
        lastClickedFileID = item.id
    }

    func rangeSelectFile(_ item: FileItem) {
        let flat = visibleFlatFiles()
        guard let anchorID = lastClickedFileID,
              let anchorIdx = flat.firstIndex(where: { $0.id == anchorID }),
              let targetIdx = flat.firstIndex(where: { $0.id == item.id }) else {
            plainClickFile(item)
            return
        }
        let range = min(anchorIdx, targetIdx)...max(anchorIdx, targetIdx)
        selectedFileIDs = Set(flat[range].map(\.id))
    }

    func extendSelection(to item: FileItem) {
        selectedFileIDs.insert(item.id)
        lastClickedFileID = item.id
    }

    func clearFileSelection() {
        selectedFileIDs.removeAll()
        lastClickedFileID = nil
    }

    func selectedFileItems() -> [FileItem] {
        let flat = visibleFlatFiles()
        return flat.filter { selectedFileIDs.contains($0.id) }
    }

    // MARK: - Reveal in File Browser

    func revealFileInBrowser(_ fileID: String) {
        guard let repositoryURL else { return }

        let repoPath = repositoryURL.path
        guard fileID.hasPrefix(repoPath) else { return }

        let relativePath = String(fileID.dropFirst(repoPath.count + 1))
        let components = relativePath.split(separator: "/").dropLast()
        var currentPath = repoPath
        for component in components {
            currentPath += "/\(component)"
            if !expandedPaths.contains(currentPath) {
                expandedPaths.insert(currentPath)
                loadChildrenIfNeeded(for: currentPath)
            }
        }

        selectedFileIDs = [fileID]
        lastClickedFileID = fileID
        revealFileInBrowserRequestID += 1
    }

    // MARK: - Editor Symbol Integration

    func findEditorDefinitions(for query: EditorSymbolQuery) async -> [EditorSymbolLocation] {
        guard let repositoryURL else { return [] }
        return await editorSymbolIndex.definitions(for: query, repositoryURL: repositoryURL)
    }

    func findEditorReferences(for query: EditorSymbolQuery) async -> [EditorSymbolLocation] {
        guard let repositoryURL else { return [] }
        return await editorSymbolIndex.references(for: query, repositoryURL: repositoryURL)
    }

    func openEditorLocation(_ location: EditorSymbolLocation) {
        guard let repositoryURL else { return }
        let targetURL = repositoryURL.appendingPathComponent(location.relativePath)
        let item = FileItem(url: targetURL, isDirectory: false, children: nil)
        selectCodeFile(item)

        let targetID = item.id
        let targetLine = max(1, location.line)
        Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<Constants.Limits.maxEditorLocationWaitAttempts {
                if selectedCodeFile?.id == targetID, originalFileContents[targetID] != nil {
                    break
                }
                try? await Task.sleep(for: .milliseconds(Constants.Limits.editorLocationWaitIntervalMs))
            }
            editorJumpLineTarget = targetLine
            editorJumpToken += 1
        }
    }

    // MARK: - Find in Files

    func findInFiles(
        query: String,
        includePattern: String = "",
        excludePattern: String = "",
        scopePath: String? = nil
    ) async -> [FindInFilesFileResult] {
        guard let repositoryURL, !query.isEmpty else { return [] }

        var args = ["grep", "-n", "-I", "--no-color", "-F", "-e", query]

        // Include patterns (e.g. "*.swift" or "*.ts,*.js")
        let includes = includePattern.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        // Exclude patterns
        let excludes = excludePattern.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        // Separator between flags and pathspecs
        args.append("--")

        // Include pathspecs
        for inc in includes {
            args.append(inc)
        }

        // Exclude pathspecs
        for exc in excludes {
            args.append(":(exclude)\(exc)")
        }

        // Scope to a specific sub-directory
        if let scopePath {
            let relative = scopePath.hasPrefix(repositoryURL.path)
                ? String(scopePath.dropFirst(repositoryURL.path.count).drop(while: { $0 == "/" }))
                : scopePath
            if !relative.isEmpty {
                args.append(relative)
            }
        }

        do {
            let output = try await worker.runGitCommand(in: repositoryURL, args: args)
            return Self.parseFindInFilesOutput(
                output,
                query: query,
                maxMatches: Constants.Limits.maxFindInFilesMatches
            )
        } catch {
            // git grep returns non-zero when no matches — not a real error
            return []
        }
    }

    static func parseFindInFilesOutput(_ output: String, maxMatches: Int) -> [FindInFilesFileResult] {
        parseFindInFilesOutputInternal(output, query: nil, maxMatches: maxMatches)
    }

    static func parseFindInFilesOutput(_ output: String, query: String, maxMatches: Int) -> [FindInFilesFileResult] {
        parseFindInFilesOutputInternal(output, query: query, maxMatches: maxMatches)
    }

    private static func parseFindInFilesOutputInternal(
        _ output: String,
        query: String?,
        maxMatches: Int
    ) -> [FindInFilesFileResult] {
        var byFile: [String: [FindInFilesMatch]] = [:]
        var fileOrder: [String] = []
        var totalMatches = 0

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard totalMatches < maxMatches else { break }

            // Format: file:lineNo:content
            let str = String(line)
            guard let firstColon = str.firstIndex(of: ":") else { continue }
            let file = String(str[str.startIndex..<firstColon])

            let afterFile = str[str.index(after: firstColon)...]
            guard let secondColon = afterFile.firstIndex(of: ":") else { continue }
            let lineNoStr = String(afterFile[afterFile.startIndex..<secondColon])
            guard let lineNo = Int(lineNoStr) else { continue }

            let content = String(afterFile[afterFile.index(after: secondColon)...])
                .trimmingCharacters(in: .init(charactersIn: "\r"))

            if byFile[file] == nil {
                fileOrder.append(file)
            }

            let preview = String(content.prefix(200))
            let locatedMatches = query.map { findInFilesMatchLocations(in: content, query: $0) } ?? []

            if locatedMatches.isEmpty {
                let match = FindInFilesMatch(
                    file: file,
                    line: lineNo,
                    preview: preview
                )
                byFile[file, default: []].append(match)
                totalMatches += 1
                continue
            }

            for locatedMatch in locatedMatches {
                guard totalMatches < maxMatches else { break }
                let match = FindInFilesMatch(
                    file: file,
                    line: lineNo,
                    preview: preview,
                    column: locatedMatch.column,
                    matchLength: locatedMatch.length
                )
                byFile[file, default: []].append(match)
                totalMatches += 1
            }
        }

        return fileOrder.compactMap { file in
            guard let matches = byFile[file] else { return nil }
            return FindInFilesFileResult(file: file, matches: matches)
        }
    }

    private static func findInFilesMatchLocations(in text: String, query: String) -> [(column: Int, length: Int)] {
        guard !text.isEmpty, !query.isEmpty else { return [] }

        let nsText = text as NSString
        var searchRange = NSRange(location: 0, length: nsText.length)
        var matches: [(column: Int, length: Int)] = []

        while searchRange.length > 0 {
            let foundRange = nsText.range(of: query, options: [], range: searchRange)
            guard foundRange.location != NSNotFound else { break }

            matches.append((column: foundRange.location + 1, length: foundRange.length))

            let nextLocation = foundRange.location + max(foundRange.length, 1)
            guard nextLocation < nsText.length else { break }
            searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
        }

        return matches
    }

    // MARK: - Replace in Files

    func replaceInFile(
        match: FindInFilesMatch,
        query: String,
        replacement: String
    ) -> Bool {
        guard let repositoryURL else { return false }
        let fileURL = repositoryURL.appendingPathComponent(match.file)
        do {
            let sourceContent = try replacementSourceContent(for: fileURL)
            guard let updatedContent = Self.replacingMatch(
                in: sourceContent,
                match: match,
                query: query,
                replacement: replacement
            ) else {
                return false
            }

            try updatedContent.write(to: fileURL, atomically: true, encoding: .utf8)
            synchronizeOpenEditorState(for: fileURL, content: updatedContent)
            registerReplaceUndo(
                previousContents: [normalizedEditorURL(fileURL).path: sourceContent],
                updatedContents: [normalizedEditorURL(fileURL).path: updatedContent]
            )

            return true
        } catch {
            return false
        }
    }

    func replaceAllInFiles(
        results: [FindInFilesFileResult],
        query: String,
        replacement: String
    ) -> Int {
        guard let repositoryURL, !query.isEmpty else { return 0 }
        var totalReplacements = 0
        var previousContents: [String: String] = [:]
        var updatedContents: [String: String] = [:]

        for fileResult in results {
            let fileURL = repositoryURL.appendingPathComponent(fileResult.file)
            do {
                let sourceContent = try replacementSourceContent(for: fileURL)
                let replacementCount = Self.findInFilesMatchLocations(in: sourceContent, query: query).count
                guard replacementCount > 0 else { continue }

                let updatedContent = sourceContent.replacingOccurrences(of: query, with: replacement)
                totalReplacements += replacementCount

                try updatedContent.write(to: fileURL, atomically: true, encoding: .utf8)
                synchronizeOpenEditorState(for: fileURL, content: updatedContent)
                let fileID = normalizedEditorURL(fileURL).path
                previousContents[fileID] = sourceContent
                updatedContents[fileID] = updatedContent
            } catch {
                continue
            }
        }

        registerReplaceUndo(previousContents: previousContents, updatedContents: updatedContents)
        refreshFileTree()
        return totalReplacements
    }

    private func replacementSourceContent(for fileURL: URL) throws -> String {
        let fileID = normalizedEditorURL(fileURL).path
        if let draft = draftFileContents[fileID] {
            return draft
        }
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func synchronizeOpenEditorState(for fileURL: URL, content: String) {
        let fileID = normalizedEditorURL(fileURL).path
        guard activeFileID == fileID || openedFiles.contains(where: { $0.id == fileID }) else { return }

        if activeFileID == fileID {
            originalFileContents[fileID] = content
            draftFileContents[fileID] = content
            unsavedFiles.remove(fileID)
            isApplyingEditorContent = true
            codeFileContent = content
            isApplyingEditorContent = false
            return
        }

        let file = openedFiles.first(where: { $0.id == fileID })
            ?? FileItem(url: fileURL, isDirectory: false, children: nil)
        applySavedContent(content, to: file)
    }

    private func registerReplaceUndo(
        previousContents: [String: String],
        updatedContents: [String: String]
    ) {
        guard !previousContents.isEmpty,
              Set(previousContents.keys) == Set(updatedContents.keys) else {
            return
        }
        replaceUndoStack.append(
            ReplaceUndoEntry(
                targetContents: previousContents,
                inverseContents: updatedContents
            )
        )
        replaceRedoStack.removeAll()
        logger.log(
            .info,
            "replace.history.push",
            context: "files=\(previousContents.count) undoStack=\(replaceUndoStack.count) redoStack=\(replaceRedoStack.count)",
            source: #function
        )
    }

    private func performWorkspaceReplaceUndo() {
        guard let entry = replaceUndoStack.popLast() else { return }
        logger.log(
            .info,
            "replace.history.undo",
            context: "files=\(entry.targetContents.count) undoStack=\(replaceUndoStack.count) redoStack=\(replaceRedoStack.count)",
            source: #function
        )
        applyReplaceHistoryEntry(entry, destinationStack: \.replaceRedoStack)
    }

    private func performWorkspaceReplaceRedo() {
        guard let entry = replaceRedoStack.popLast() else { return }
        logger.log(
            .info,
            "replace.history.redo",
            context: "files=\(entry.targetContents.count) undoStack=\(replaceUndoStack.count) redoStack=\(replaceRedoStack.count)",
            source: #function
        )
        applyReplaceHistoryEntry(entry, destinationStack: \.replaceUndoStack)
    }

    private func applyReplaceHistoryEntry(
        _ entry: ReplaceUndoEntry,
        destinationStack: ReferenceWritableKeyPath<RepositoryViewModel, [ReplaceUndoEntry]>
    ) {
        applyReplaceSnapshot(
            entry.targetContents,
            inverseContents: entry.inverseContents,
            destinationStack: destinationStack
        )
    }

    private func applyReplaceSnapshot(
        _ targetContents: [String: String],
        inverseContents: [String: String],
        destinationStack: ReferenceWritableKeyPath<RepositoryViewModel, [ReplaceUndoEntry]>
    ) {
        guard !targetContents.isEmpty,
              Set(targetContents.keys) == Set(inverseContents.keys) else {
            return
        }

        var appliedPaths: [String] = []
        for (path, content) in targetContents {
            let fileURL = URL(fileURLWithPath: path)
            do {
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                synchronizeOpenEditorState(for: fileURL, content: content)
                appliedPaths.append(path)
            } catch {
                continue
            }
        }

        guard !appliedPaths.isEmpty else { return }

        let destinationTarget: [String: String] = appliedPaths.reduce(into: [:]) { partialResult, path in
            if let content = inverseContents[path] {
                partialResult[path] = content
            }
        }
        let destinationInverse: [String: String] = appliedPaths.reduce(into: [:]) { partialResult, path in
            if let content = targetContents[path] {
                partialResult[path] = content
            }
        }
        self[keyPath: destinationStack].append(
            ReplaceUndoEntry(
                targetContents: destinationTarget,
                inverseContents: destinationInverse
            )
        )
        logger.log(
            .info,
            "replace.history.apply",
            context: "applied=\(appliedPaths.count) destinationUndo=\(replaceUndoStack.count) destinationRedo=\(replaceRedoStack.count)",
            source: #function
        )

        refreshFileTree()
    }

    private func debugFirstResponderDescription() -> String {
        guard let responder = NSApplication.shared.keyWindow?.firstResponder else { return "nil" }
        return String(describing: type(of: responder))
    }

    private static func replacingMatch(
        in content: String,
        match: FindInFilesMatch,
        query: String,
        replacement: String
    ) -> String? {
        let lines = content.components(separatedBy: "\n")
        let lineIndex = match.line - 1
        guard lineIndex >= 0, lineIndex < lines.count else { return nil }

        let originalLine = lines[lineIndex]
        let nsLine = originalLine as NSString
        let replacementRange: NSRange

        if let column = match.column {
            let rangeLength = match.matchLength ?? (query as NSString).length
            let candidateRange = NSRange(location: column - 1, length: rangeLength)
            guard candidateRange.location >= 0,
                  NSMaxRange(candidateRange) <= nsLine.length,
                  nsLine.substring(with: candidateRange) == query else {
                return nil
            }
            replacementRange = candidateRange
        } else {
            let foundRange = nsLine.range(of: query)
            guard foundRange.location != NSNotFound else { return nil }
            replacementRange = foundRange
        }

        guard let swiftRange = Range(replacementRange, in: originalLine) else { return nil }

        var updatedLines = lines
        var updatedLine = originalLine
        updatedLine.replaceSubrange(swiftRange, with: replacement)
        updatedLines[lineIndex] = updatedLine
        return updatedLines.joined(separator: "\n")
    }

    // MARK: - Flat File Helpers

    func allFlatFiles() -> [FileItem] {
        if isFlatFileCacheDirty {
            rebuildFlatFileCache()
        }
        return flatFileCache
    }

    /// Returns all visible items in the file browser tree (directories + files),
    /// respecting the current expansion state. Used for keyboard navigation.
    func visibleFlatFiles() -> [FileItem] {
        func walk(_ items: [FileItem]) -> [FileItem] {
            var result: [FileItem] = []
            for item in items {
                result.append(item)
                if item.isDirectory && expandedPaths.contains(item.id),
                   let children = item.children {
                    result.append(contentsOf: walk(children))
                }
            }
            return result
        }
        return walk(repositoryFiles)
    }

    func pruneStaleSelections() {
        guard !selectedFileIDs.isEmpty else { return }
        let validIDs = Set(allFlatFiles().map(\.id))
        selectedFileIDs.formIntersection(validIDs)
    }

    func rebuildFlatFileCache() {
        func flatten(_ items: [FileItem]) -> [FileItem] {
            var result: [FileItem] = []
            for item in items {
                if item.isDirectory {
                    if let children = item.children {
                        result.append(contentsOf: flatten(children))
                    }
                } else {
                    result.append(item)
                }
            }
            return result
        }
        flatFileCache = flatten(repositoryFiles)
        isFlatFileCacheDirty = false
    }

    func scheduleEditorSymbolIndexRebuild(repositoryURL: URL) {
        if symbolIndexRebuildRepositoryURL == repositoryURL,
           let lastSymbolIndexRebuildAt,
           Date().timeIntervalSince(lastSymbolIndexRebuildAt) < ignoredPathsCacheTTL {
            return
        }
        editorSymbolIndexTask?.cancel()
        editorSymbolIndexTask = Task(priority: .utility) { [weak self, editorSymbolIndex] in
            try? await Task.sleep(for: .seconds(1.2))
            guard let self else { return }
            guard self.repositoryURL == repositoryURL else { return }
            await editorSymbolIndex.rebuild(repositoryURL: repositoryURL)
            guard self.repositoryURL == repositoryURL else { return }
            self.symbolIndexRebuildRepositoryURL = repositoryURL
            self.lastSymbolIndexRebuildAt = Date()
        }
    }

    func toggleExpansion(for path: String) {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
        } else {
            expandedPaths.insert(path)
            loadChildrenIfNeeded(for: path)
        }
        if let repositoryURL {
            expandedPathsByRepository[repositoryURL] = expandedPaths
            captureRepositorySnapshot(for: repositoryURL)
        }
    }
}
