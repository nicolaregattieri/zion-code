import Foundation
import SwiftUI

extension RepositoryViewModel {

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

        var args = ["grep", "-n", "-I", "--no-color", "-e", query]

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
            return Self.parseFindInFilesOutput(output, maxMatches: Constants.Limits.maxFindInFilesMatches)
        } catch {
            // git grep returns non-zero when no matches — not a real error
            return []
        }
    }

    static func parseFindInFilesOutput(_ output: String, maxMatches: Int) -> [FindInFilesFileResult] {
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

            let match = FindInFilesMatch(
                file: file,
                line: lineNo,
                preview: String(content.prefix(200))
            )

            if byFile[file] == nil {
                fileOrder.append(file)
            }
            byFile[file, default: []].append(match)
            totalMatches += 1
        }

        return fileOrder.compactMap { file in
            guard let matches = byFile[file] else { return nil }
            return FindInFilesFileResult(file: file, matches: matches)
        }
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
