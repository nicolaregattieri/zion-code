import Foundation
import SwiftUI
import UniformTypeIdentifiers

private enum EditorFilePreparationResult: Sendable {
    case missing
    case ready(kind: EditorContentKind, content: String?)
    case readFailure(String)
}

private enum EditorFileSaveResult {
    case saved(fileID: String)
    case cancelled
    case failed
}

private enum EditorFileClosePreparation {
    case ready(fileID: String)
    case cancelled
}

private enum EditorFileInspector {
    static let acceptedTextTypes: [UTType] = [
        .text, .plainText, .sourceCode, .shellScript, .script,
        .json, .xml, .yaml, .html,
    ]

    static let acceptedImageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "tif", "svg",
    ]

    static func contentKind(for url: URL) -> EditorContentKind {
        let ext = url.pathExtension.lowercased()
        if ext == "md" || ext == "markdown" {
            return .markdown
        }
        if ext == "svg" || acceptedImageExtensions.contains(ext) {
            return .image
        }
        if url.path.hasPrefix(ZionTemp.directory.path) {
            return .text
        }
        if isImageFile(url) {
            return .image
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            return .text
        }
        return isTextFile(url) ? .text : .unsupported
    }

    static func isTextFile(_ url: URL) -> Bool {
        guard let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey]),
              let contentType = resourceValues.contentType else {
            return isLikelyTextFileByContent(url)
        }
        if acceptedTextTypes.contains(where: { contentType.conforms(to: $0) }) {
            return true
        }
        return isLikelyTextFileByContent(url)
    }

    static func isImageFile(_ url: URL) -> Bool {
        if let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey]),
           let contentType = resourceValues.contentType,
           contentType.conforms(to: .image) {
            return true
        }
        let ext = url.pathExtension.lowercased()
        if ext == "svg" {
            return true
        }
        return acceptedImageExtensions.contains(ext)
    }

    static func prepareForEditor(url: URL) -> EditorFilePreparationResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .missing
        }

        let kind = contentKind(for: url)
        guard kind == .text || kind == .markdown else {
            return .ready(kind: kind, content: nil)
        }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            return .ready(kind: kind, content: content)
        } catch {
            if !FileManager.default.fileExists(atPath: url.path) {
                return .missing
            }
            return .readFailure(error.localizedDescription)
        }
    }

    private static func isLikelyTextFileByContent(_ url: URL, maxBytes: Int = 8_192) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes) else { return false }
        if data.isEmpty { return true }
        if data.contains(0) { return false }
        if String(data: data, encoding: .utf8) != nil { return true }
        if String(data: data, encoding: .ascii) != nil { return true }
        return false
    }
}

extension RepositoryViewModel {

    // MARK: - Zion Code Methods

    func refreshFileTree(forceReloadExpandedDirectories: Bool = true) {
        guard let url = repositoryURL else { return }
        let requestID = UUID()
        fileTreeRefreshRequestID = requestID
        fileTreeRefreshTask?.cancel()
        fileTreeRefreshTask = Task { [weak self] in
            guard let self else { return }
            // Phase 1: load top-level only (instant)
            let initial = await self.loadFiles(at: url, ignoredPaths: nil, maxDepth: 0)
            guard !Task.isCancelled else { return }

            // Phase 2: refine with gitignore — build final value before assigning
            let ignoredPaths = await self.loadGitIgnoredPaths(for: url)
            let files: [FileItem]
            if !ignoredPaths.isEmpty {
                files = await self.loadFiles(at: url, ignoredPaths: ignoredPaths, maxDepth: 0)
            } else {
                files = initial
            }

            guard !Task.isCancelled else { return }
            guard self.fileTreeRefreshRequestID == requestID, self.repositoryURL == url else { return }

            self.repositoryFiles = self.mergeTopLevel(old: self.repositoryFiles, new: files)
            self.reloadExpandedDirectories(forceReload: forceReloadExpandedDirectories)
            self.pruneStaleSelections()
            self.recalculateMissingOpenFileState(updateEditorForActiveFile: true)
            self.expandedPathsByRepository[url] = self.expandedPaths
            self.captureRepositorySnapshot(for: url)
            self.scheduleEditorSymbolIndexRebuild(repositoryURL: url)
        }
    }

    func reloadExpandedDirectories(forceReload: Bool = false) {
        guard let repositoryURL else { return }
        guard !_isReloadingExpandedDirs else { return }
        _isReloadingExpandedDirs = true
        defer { _isReloadingExpandedDirs = false }
        for path in expandedPaths {
            loadChildrenIfNeeded(for: path, forceReload: forceReload, expectedRepositoryURL: repositoryURL)
        }
    }

    /// Merges new top-level items into the existing tree, preserving loaded children
    /// on directories that still exist. This avoids the collapse-then-expand flicker
    /// caused by replacing the entire array.
    func mergeTopLevel(old: [FileItem], new: [FileItem]) -> [FileItem] {
        mergeDirectoryChildren(old: old, new: new)
    }

    /// Merge directory children while preserving already loaded descendants to avoid
    /// expansion flicker during external file updates.
    func mergeDirectoryChildren(old: [FileItem], new: [FileItem]) -> [FileItem] {
        let oldByID = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        return new.map { newItem in
            if let existing = oldByID[newItem.id],
               newItem.isDirectory,
               existing.isDirectory,
               existing.children != nil {
                // Preserve loaded children from the existing item
                return FileItem(
                    url: newItem.url,
                    isDirectory: true,
                    children: existing.children,
                    isGitIgnored: newItem.isGitIgnored
                )
            }
            return newItem
        }
    }

    func loadChildrenIfNeeded(
        for path: String,
        forceReload: Bool = false,
        expectedRepositoryURL: URL? = nil
    ) {
        guard let repositoryURL else { return }
        let targetRepositoryURL = expectedRepositoryURL ?? repositoryURL
        guard repositoryURL == targetRepositoryURL else { return }
        guard let item = findItem(path: path, in: repositoryFiles),
              item.isDirectory,
              item.children == nil || forceReload else { return }
        let itemURL = item.url
        let existingChildren = item.children ?? []
        let ignoredPaths = cachedIgnoredPaths
        Task { [weak self] in
            guard let self else { return }
            let children = await self.loadFiles(at: itemURL, ignoredPaths: ignoredPaths, maxDepth: 0)
            guard !Task.isCancelled else { return }
            guard self.repositoryURL == targetRepositoryURL else { return }
            let mergedChildren = self.mergeDirectoryChildren(old: existingChildren, new: children)
            self.repositoryFiles = self.updateTree(self.repositoryFiles, path: path, newChildren: mergedChildren)
            self.captureRepositorySnapshot(for: targetRepositoryURL)
            // Breadcrumb/path navigation can request deep expansions before parent nodes
            // finish loading. Re-run pending expanded paths so deeper levels load as soon
            // as they become discoverable in the tree.
            self.reloadExpandedDirectories()
        }
    }

    func findItem(path: String, in items: [FileItem]) -> FileItem? {
        for item in items {
            if item.id == path { return item }
            if let children = item.children,
               let found = findItem(path: path, in: children) {
                return found
            }
        }
        return nil
    }

    func updateTree(_ items: [FileItem], path: String, newChildren: [FileItem]) -> [FileItem] {
        items.map { item in
            if item.id == path {
                return FileItem(url: item.url, isDirectory: item.isDirectory, children: newChildren, isGitIgnored: item.isGitIgnored)
            }
            if let children = item.children {
                return FileItem(url: item.url, isDirectory: item.isDirectory,
                              children: updateTree(children, path: path, newChildren: newChildren), isGitIgnored: item.isGitIgnored)
            }
            return item
        }
    }

    // Always hidden — performance/safety, never hand-edited
    static let alwaysHiddenEntries: Set<String> = [
        "node_modules", ".git", ".DS_Store", "__pycache__", "DerivedData",
        ".build", ".swiftpm", "Pods", ".gradle", ".tox",
        ".mypy_cache", ".pytest_cache"
    ]

    // Build/tool directories — hidden by default
    static let toolDirectories: Set<String> = [
        "dist", "build", ".next", ".turbo", ".vercel", ".expo",
        ".nuxt", ".output", "coverage", ".cache", "vendor", ".idea", ".vscode"
    ]

    func loadGitIgnoredPaths(for repositoryURL: URL, forceRefresh: Bool = false) async -> Set<String> {
        if !forceRefresh,
           let cached = ignoredPathsCacheByRepository[repositoryURL],
           Date().timeIntervalSince(cached.capturedAt) <= ignoredPathsCacheTTL {
            cachedIgnoredPaths = cached.paths
            return cached.paths
        }
        do {
            let output = try await worker.runAction(
                args: ["ls-files", "--others", "--ignored", "--exclude-standard", "--directory"],
                in: repositoryURL
            )
            let paths = output.split(separator: "\n").map {
                // git outputs paths relative to repo root, trailing / for dirs
                repositoryURL.appendingPathComponent(String($0).trimmingCharacters(in: CharacterSet(charactersIn: "/"))).path
            }
            let resolved = Set(paths)
            ignoredPathsCacheByRepository[repositoryURL] = IgnoredPathsCacheEntry(
                paths: resolved,
                capturedAt: Date()
            )
            if self.repositoryURL == repositoryURL {
                cachedIgnoredPaths = resolved
            }
            return resolved
        } catch {
            logger.log(.warn, "Failed to load gitignored paths: \(error.localizedDescription)", source: #function)
            return []
        }
    }

    func loadFiles(at url: URL, ignoredPaths: Set<String>? = nil, maxDepth: Int = .max) async -> [FileItem] {
        let fm = FileManager.default
        do {
            let options: FileManager.DirectoryEnumerationOptions = showDotfiles ? [] : [.skipsHiddenFiles]
            let contents = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: options)
            var items: [FileItem] = []
            for item in contents {
                let name = item.lastPathComponent

                // Skip always-hidden entries (node_modules, .git, etc.)
                if Self.alwaysHiddenEntries.contains(name) || name.hasSuffix(".egg-info") { continue }
                // Skip build/tool directories
                if Self.toolDirectories.contains(name) { continue }

                let isIgnored = ignoredPaths?.contains(item.path) ?? false

                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let children: [FileItem]?
                if isDir && maxDepth > 0 {
                    children = await loadFiles(at: item, ignoredPaths: ignoredPaths, maxDepth: maxDepth - 1)
                } else if isDir {
                    children = nil // Directory but children not loaded yet (lazy)
                } else {
                    children = nil
                }
                items.append(FileItem(url: item, isDirectory: isDir, children: children?.sorted(by: { $0.name.lowercased() < $1.name.lowercased() }), isGitIgnored: isIgnored))
            }
            return items.sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.lowercased() < b.name.lowercased()
            }
        } catch {
            logger.log(.warn, "Failed to load files: \(error.localizedDescription)", context: url.path, source: #function)
            return []
        }
    }

    func isOpenFileMissingOnDisk(_ file: FileItem) -> Bool {
        !FileManager.default.fileExists(atPath: file.url.path)
    }

    func recalculateMissingOpenFileState(updateEditorForActiveFile: Bool) {
        let missing = Set(openedFiles.compactMap { file in
            isOpenFileMissingOnDisk(file) ? file.id : nil
        })
        missingOpenFileIDs = missing

        guard updateEditorForActiveFile,
              let activeFileID,
              missing.contains(activeFileID),
              let selectedCodeFile,
              selectedCodeFile.id == activeFileID else { return }
        displayMissingEditorState(for: selectedCodeFile)
    }

    func normalizedEditorURL(_ url: URL) -> URL {
        url.standardizedFileURL
    }

    func normalizedEditorItem(_ item: FileItem) -> FileItem {
        FileItem(
            url: normalizedEditorURL(item.url),
            isDirectory: item.isDirectory,
            children: item.children,
            isGitIgnored: item.isGitIgnored
        )
    }

    func applyEditorContent(_ content: String, syncDraftFor fileID: String? = nil) {
        isApplyingEditorContent = true
        codeFileContent = content
        isApplyingEditorContent = false

        guard let fileID else { return }
        draftFileContents[fileID] = content
        markFileUnsavedState(fileID: fileID)
    }

    func syncActiveDraftFromEditorContent() {
        guard let file = selectedCodeFile else { return }
        let kind = editorContentKind(for: file.url)
        guard kind == .text || kind == .markdown else { return }
        draftFileContents[file.id] = codeFileContent
        markFileUnsavedState(fileID: file.id)
    }

    func markFileUnsavedState(fileID: String) {
        guard let original = originalFileContents[fileID],
              let draft = draftFileContents[fileID] else {
            unsavedFiles.remove(fileID)
            return
        }
        if original != draft {
            unsavedFiles.insert(fileID)
        } else {
            unsavedFiles.remove(fileID)
        }
    }

    func isDraftBuffered(for fileID: String) -> Bool {
        draftFileContents[fileID] != nil
    }

    func restoreDraftIfAvailable(for item: FileItem) -> Bool {
        guard let draft = draftFileContents[item.id] else { return false }
        applyEditorContent(draft)
        markFileUnsavedState(fileID: item.id)
        return true
    }

    func displayMissingEditorState(for item: FileItem) {
        missingOpenFileIDs.insert(item.id)
        statusMessage = L10n("editor.file.missingStatus", item.name)

        if restoreDraftIfAvailable(for: item) {
            return
        }

        isApplyingEditorContent = true
        codeFileContent = L10n("editor.file.missingContent")
        isApplyingEditorContent = false
        unsavedFiles.remove(item.id)
    }

    @discardableResult
    func promptToCloseDirtyFile(_ item: FileItem) -> EditorDirtyCloseDecision {
        if let handler = dirtyFileCloseDecisionHandler {
            return handler(item)
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n("editor.tab.unsavedClose.title")
        alert.informativeText = L10n("editor.tab.unsavedClose.message", item.name)
        alert.addButton(withTitle: L10n("Salvar"))
        alert.addButton(withTitle: L10n("Descartar"))
        alert.addButton(withTitle: L10n("Cancelar"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save
        case .alertSecondButtonReturn:
            return .discard
        default:
            return .cancel
        }
    }

    fileprivate func prepareFileForClosing(_ item: FileItem) -> EditorFileClosePreparation {
        guard unsavedFiles.contains(item.id) else {
            return .ready(fileID: item.id)
        }

        switch promptToCloseDirtyFile(item) {
        case .save:
            switch saveEditorFile(item) {
            case let .saved(fileID):
                return .ready(fileID: fileID)
            case .cancelled, .failed:
                return .cancelled
            }
        case .discard:
            return .ready(fileID: item.id)
        case .cancel:
            return .cancelled
        }
    }

    func performCloseFile(id: String, discardDraft: Bool) {
        guard let index = openedFiles.firstIndex(where: { $0.id == id }) else { return }

        openedFiles.remove(at: index)
        missingOpenFileIDs.remove(id)
        if discardDraft {
            draftFileContents.removeValue(forKey: id)
        }
        originalFileContents.removeValue(forKey: id)
        unsavedFiles.remove(id)

        if activeFileID == id {
            if let last = openedFiles.last {
                selectCodeFile(last)
            } else {
                activeFileID = nil
                selectedCodeFile = nil
                applyEditorContent("", syncDraftFor: nil)
            }
        }
        recalculateMissingOpenFileState(updateEditorForActiveFile: false)
    }

    func saveDraftContent(for fileID: String) -> String? {
        if let draft = draftFileContents[fileID] {
            return draft
        }
        if activeFileID == fileID {
            return codeFileContent
        }
        return nil
    }

    func formatEditorContentForSave(_ content: String, file: FileItem) -> String {
        guard editorFormatOnSave else { return content }
        let ext = file.url.pathExtension
        guard CodeFormatter.canFormat(fileExtension: ext) else { return content }

        let opts = FormatOptions(
            tabSize: effectiveTabSize,
            useTabs: editorUseTabs,
            jsonSortKeys: editorJsonSortKeys
        )

        if case let .success(formatted) = CodeFormatter.format(content, fileExtension: ext, options: opts) {
            return formatted
        }
        return content
    }

    func applySavedContent(_ content: String, to file: FileItem) {
        draftFileContents[file.id] = content
        originalFileContents[file.id] = content
        unsavedFiles.remove(file.id)

        if activeFileID == file.id {
            applyEditorContent(content, syncDraftFor: file.id)
        }
    }

    fileprivate func saveEditorFile(_ file: FileItem) -> EditorFileSaveResult {
        if missingOpenFileIDs.contains(file.id) {
            statusMessage = L10n("editor.file.missingSaveBlocked")
            return .failed
        }

        let kind = editorContentKind(for: file.url)
        guard kind == .text || kind == .markdown else {
            statusMessage = L10n("editor.file.readOnlyBinary")
            return .failed
        }

        guard let currentContent = saveDraftContent(for: file.id) else {
            return .failed
        }

        let content = formatEditorContentForSave(currentContent, file: file)

        if file.url.path.hasPrefix(ZionTemp.directory.path) {
            return saveEditorFileAs(file, content: content)
        }

        do {
            try content.write(to: file.url, atomically: true, encoding: .utf8)
            statusMessage = String(format: L10n("Arquivo salvo: %@"), file.name)
            applySavedContent(content, to: file)
            refreshRepository()
            return .saved(fileID: file.id)
        } catch {
            handleError(error)
            return .failed
        }
    }

    fileprivate func saveEditorFileAs(_ file: FileItem, content: String? = nil) -> EditorFileSaveResult {
        let kind = editorContentKind(for: file.url)
        guard kind == .text || kind == .markdown else {
            statusMessage = L10n("editor.file.readOnlyBinary")
            return .failed
        }

        let draftContent = content ?? saveDraftContent(for: file.id) ?? ""
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.name
        panel.canCreateDirectories = true
        if let repoURL = repositoryURL {
            panel.directoryURL = repoURL
        }
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }

        do {
            try draftContent.write(to: url, atomically: true, encoding: .utf8)
            let newItem = FileItem(url: url, isDirectory: false, children: nil)
            let oldID = file.id
            if let idx = openedFiles.firstIndex(where: { $0.id == oldID }) {
                openedFiles[idx] = newItem
            } else {
                openedFiles.append(newItem)
            }
            if activeFileID == oldID {
                activeFileID = newItem.id
                selectedCodeFile = newItem
            }

            originalFileContents.removeValue(forKey: oldID)
            draftFileContents.removeValue(forKey: oldID)
            unsavedFiles.remove(oldID)
            missingOpenFileIDs.remove(oldID)

            draftFileContents[newItem.id] = draftContent
            originalFileContents[newItem.id] = draftContent
            unsavedFiles.remove(newItem.id)

            if activeFileID == newItem.id {
                applyEditorContent(draftContent, syncDraftFor: newItem.id)
            }

            statusMessage = String(format: L10n("Arquivo salvo: %@"), newItem.name)
            refreshRepository()
            return .saved(fileID: newItem.id)
        } catch {
            handleError(error)
            return .failed
        }
    }

    func attemptCloseFiles(ids: [String], discardDraft: Bool = true) {
        for id in ids {
            guard let file = openedFiles.first(where: { $0.id == id }) else { continue }
            switch prepareFileForClosing(file) {
            case let .ready(fileID):
                performCloseFile(id: fileID, discardDraft: discardDraft)
            case .cancelled:
                return
            }
        }
    }

    func activateFileInEditor(_ item: FileItem, highlightQuery: String? = nil, navigateToCode: Bool = false) {
        guard !item.isDirectory else { return }

        let normalizedItem = normalizedEditorItem(item)
        let activeItem: FileItem
        if let existing = openedFiles.first(where: { $0.id == normalizedItem.id }) {
            activeItem = existing
        } else {
            openedFiles.append(normalizedItem)
            activeItem = normalizedItem
        }

        activeFileID = activeItem.id
        selectedCodeFile = activeItem
        editorFocusRequestID += 1
        if restoreDraftIfAvailable(for: activeItem) {
            if navigateToCode {
                navigateToCodeRequested = true
            }
            if let highlightQuery {
                let query = highlightQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty {
                    editorFindSeedQuery = query
                    editorFindSeedRequestID += 1
                }
            }
            return
        }

        applyEditorContent("", syncDraftFor: nil)
        let itemURL = activeItem.url
        let itemID = activeItem.id
        Task { [itemURL, itemID] in
            let prepared = await Task.detached(priority: .userInitiated) {
                EditorFileInspector.prepareForEditor(url: itemURL)
            }.value

            guard activeFileID == itemID else { return }

            switch prepared {
            case .missing:
                displayMissingEditorState(for: activeItem)
            case let .ready(kind, content):
                missingOpenFileIDs.remove(itemID)
                if kind == .text || kind == .markdown {
                    let resolvedContent = content ?? ""
                    originalFileContents[itemID] = resolvedContent
                    if !isDraftBuffered(for: itemID) {
                        draftFileContents[itemID] = resolvedContent
                    }
                    if activeFileID == itemID, draftFileContents[itemID] == resolvedContent {
                        applyEditorContent(resolvedContent)
                    }
                    markFileUnsavedState(fileID: itemID)
                } else {
                    draftFileContents.removeValue(forKey: itemID)
                    originalFileContents.removeValue(forKey: itemID)
                    applyEditorContent("")
                    unsavedFiles.remove(itemID)
                }
            case let .readFailure(message):
                missingOpenFileIDs.remove(itemID)
                if restoreDraftIfAvailable(for: activeItem) {
                    statusMessage = message
                } else {
                    originalFileContents.removeValue(forKey: itemID)
                    draftFileContents.removeValue(forKey: itemID)
                    applyEditorContent(L10n("error.readFile", message))
                }
            }
        }

        if let highlightQuery {
            let query = highlightQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty {
                editorFindSeedQuery = query
                editorFindSeedRequestID += 1
            }
        }

        if navigateToCode {
            navigateToCodeRequested = true
        }
    }

    func selectCodeFile(_ item: FileItem) {
        activateFileInEditor(item)
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

    // MARK: - File Save/Edit

    func markCurrentFileUnsavedIfChanged() {
        guard let fileID = activeFileID else { return }
        markFileUnsavedState(fileID: fileID)
    }

    func closeFile(id: String) {
        attemptCloseFiles(ids: [id])
    }

    func closeOtherFiles(keepingID id: String) {
        guard openedFiles.contains(where: { $0.id == id }) else { return }
        let idsToClose = openedFiles.map(\.id).filter { $0 != id }
        attemptCloseFiles(ids: idsToClose)
    }

    func closeFilesToTheLeft(ofID id: String) {
        guard let index = openedFiles.firstIndex(where: { $0.id == id }), index > 0 else { return }
        let idsToClose = Array(openedFiles[..<index].map(\.id))
        attemptCloseFiles(ids: idsToClose)
    }

    func closeFilesToTheRight(ofID id: String) {
        guard let index = openedFiles.firstIndex(where: { $0.id == id }), index < openedFiles.count - 1 else { return }
        let idsToClose = Array(openedFiles[(index + 1)...].map(\.id))
        attemptCloseFiles(ids: idsToClose)
    }

    func closeAllFiles() {
        attemptCloseFiles(ids: openedFiles.map(\.id))
    }

    func saveCurrentCodeFile() {
        guard let file = selectedCodeFile else { return }
        _ = saveEditorFile(file)
    }

    func formatCurrentFile() {
        guard let file = selectedCodeFile else { return }
        let ext = file.url.pathExtension
        guard CodeFormatter.canFormat(fileExtension: ext) else {
            statusMessage = L10n("format.unsupported")
            return
        }
        let opts = FormatOptions(
            tabSize: effectiveTabSize,
            useTabs: editorUseTabs,
            jsonSortKeys: editorJsonSortKeys
        )
        switch CodeFormatter.format(codeFileContent, fileExtension: ext, options: opts) {
        case .success(let formatted):
            // Post notification for undo-aware replacement in SourceCodeEditor
            NotificationCenter.default.post(
                name: .formatCodeFile,
                object: nil,
                userInfo: ["formatted": formatted]
            )
            statusMessage = L10n("format.success")
        case .failure(let error):
            if case .noChanges = error {
                statusMessage = L10n("format.noChanges")
            } else {
                statusMessage = String(format: L10n("format.error"), error.localizedDescription)
            }
        }
    }

    func openFileInEditor(relativePath: String, highlightQuery: String? = nil) {
        guard let repoURL = repositoryURL else { return }
        let fileURL = normalizedEditorURL(repoURL.appendingPathComponent(relativePath))
        let item = FileItem(url: fileURL, isDirectory: false, children: nil)
        activateFileInEditor(item, highlightQuery: highlightQuery, navigateToCode: true)
    }

    var selectedEditorContentKind: EditorContentKind {
        guard let selectedCodeFile else { return .text }
        return editorContentKind(for: selectedCodeFile.url)
    }

    func editorContentKind(for url: URL) -> EditorContentKind {
        EditorFileInspector.contentKind(for: url)
    }

    static let acceptedTextTypes = EditorFileInspector.acceptedTextTypes
    static let acceptedImageExtensions = EditorFileInspector.acceptedImageExtensions

    func isTextFile(_ url: URL) -> Bool {
        EditorFileInspector.isTextFile(url)
    }

    func isImageFile(_ url: URL) -> Bool {
        EditorFileInspector.isImageFile(url)
    }

    func openExternalFiles(_ urls: [URL]) {
        let fileURLs = urls.filter { !$0.hasDirectoryPath && (isTextFile($0) || isImageFile($0)) }
        guard !fileURLs.isEmpty else { return }

        let repoRoot = findGitRepository(containing: fileURLs[0])

        if let repoRoot {
            if repositoryURL == repoRoot {
                openFilesAsTabs(fileURLs)
            } else {
                pendingExternalFiles = fileURLs
                openRepository(repoRoot)
            }
        } else {
            openFilesAsTabs(fileURLs)
        }
        navigateToCodeRequested = true
    }

    func findGitRepository(containing fileURL: URL) -> URL? {
        var current = fileURL.deletingLastPathComponent()
        while current.path != "/" {
            let gitDir = current.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: gitDir.path) {
                return current
            }
            current = current.deletingLastPathComponent()
        }
        return nil
    }

    func openFilesAsTabs(_ urls: [URL]) {
        for url in urls {
            let item = FileItem(url: normalizedEditorURL(url), isDirectory: false, children: nil)
            selectCodeFile(item)
        }
    }

    func createNewFile() {
        untitledCounter += 1
        let name = untitledCounter == 1 ? L10n("Sem titulo") : "\(L10n("Sem titulo")) \(untitledCounter)"
        let tempURL = ZionTemp.directory.appendingPathComponent(name)
        let item = FileItem(url: tempURL, isDirectory: false, children: nil)
        if !openedFiles.contains(where: { $0.id == item.id }) {
            openedFiles.append(item)
        }
        activeFileID = item.id
        selectedCodeFile = item
        applyEditorContent("", syncDraftFor: item.id)
        originalFileContents[item.id] = ""
        draftFileContents[item.id] = ""
    }

    func saveCurrentFileAs() {
        guard let file = selectedCodeFile else { return }
        _ = saveEditorFileAs(file)
    }

    // MARK: - File Browser Context Menu Operations

    func isSafeFileOrFolderName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        guard name != ".", name != ".." else { return false }
        guard !name.contains("/"), !name.contains("\\") else { return false }
        guard !name.contains("\0") else { return false }
        return true
    }

    func isDirectChild(_ candidateURL: URL, of parentURL: URL) -> Bool {
        let parentPath = parentURL.standardizedFileURL.path
        let candidatePath = candidateURL.standardizedFileURL.path
        return candidatePath.hasPrefix(parentPath + "/")
    }

    func reportInvalidFileOperationName() {
        handleError(NSError(
            domain: "ZionSecurity",
            code: 400,
            userInfo: [NSLocalizedDescriptionKey: "Nome de arquivo/pasta invalido."]
        ))
    }

    func createNewFileInFolder(parentURL: URL) {
        let alert = NSAlert()
        alert.messageText = L10n("Novo Arquivo")
        alert.informativeText = L10n("Nome do arquivo:")
        alert.addButton(withTitle: L10n("Criar"))
        alert.addButton(withTitle: L10n("Cancelar"))
        let input = NSTextField(frame: Constants.UI.alertInputFieldFrame)
        input.stringValue = ""
        input.placeholderString = "filename.swift"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSafeFileOrFolderName(name) else {
            reportInvalidFileOperationName()
            return
        }
        let fileURL = parentURL.appendingPathComponent(name)
        guard isDirectChild(fileURL, of: parentURL) else {
            reportInvalidFileOperationName()
            return
        }
        do {
            try "".write(to: fileURL, atomically: true, encoding: .utf8)
            refreshFileTree()
            let item = FileItem(url: fileURL, isDirectory: false, children: nil)
            selectCodeFile(item)
        } catch {
            handleError(error)
        }
    }

    func createNewFolder(parentURL: URL) {
        let alert = NSAlert()
        alert.messageText = L10n("Nova Pasta")
        alert.informativeText = L10n("Nome da pasta:")
        alert.addButton(withTitle: L10n("Criar"))
        alert.addButton(withTitle: L10n("Cancelar"))
        let input = NSTextField(frame: Constants.UI.alertInputFieldFrame)
        input.stringValue = ""
        input.placeholderString = "new-folder"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSafeFileOrFolderName(name) else {
            reportInvalidFileOperationName()
            return
        }
        let folderURL = parentURL.appendingPathComponent(name)
        guard isDirectChild(folderURL, of: parentURL) else {
            reportInvalidFileOperationName()
            return
        }
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            refreshFileTree()
        } catch {
            handleError(error)
        }
    }

    func deleteFileItem(_ item: FileItem) {
        deleteFileItems([item])
    }

    func deleteFileItems(_ items: [FileItem]) {
        guard !items.isEmpty else { return }
        let alert = NSAlert()
        if items.count == 1 {
            alert.messageText = String(format: L10n("Deseja excluir '%@'?"), items[0].name)
        } else {
            alert.messageText = String(format: L10n("Deseja excluir %d itens?"), items.count)
        }
        alert.informativeText = L10n("Esta acao nao pode ser desfeita.")
        alert.alertStyle = .critical
        alert.addButton(withTitle: L10n("Excluir"))
        alert.addButton(withTitle: L10n("Cancelar"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        for item in items {
            do {
                try FileManager.default.removeItem(at: item.url)
                if let idx = openedFiles.firstIndex(where: { $0.id == item.id }) {
                    performCloseFile(id: openedFiles[idx].id, discardDraft: true)
                }
            } catch {
                handleError(error)
            }
        }
        selectedFileIDs.subtract(items.map(\.id))
        refreshFileTree()
    }

    func renameFileItem(_ item: FileItem) {
        let alert = NSAlert()
        alert.messageText = L10n("Renomear...")
        alert.informativeText = L10n("Novo nome:")
        alert.addButton(withTitle: L10n("Confirmar"))
        alert.addButton(withTitle: L10n("Cancelar"))
        let input = NSTextField(frame: Constants.UI.alertInputFieldFrame)
        input.stringValue = item.name
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard newName != item.name else { return }
        guard isSafeFileOrFolderName(newName) else {
            reportInvalidFileOperationName()
            return
        }
        let newURL = item.url.deletingLastPathComponent().appendingPathComponent(newName)
        guard isDirectChild(newURL, of: item.url.deletingLastPathComponent()) else {
            reportInvalidFileOperationName()
            return
        }
        do {
            try FileManager.default.moveItem(at: item.url, to: newURL)
            // Update tab if open
            if let idx = openedFiles.firstIndex(where: { $0.id == item.id }) {
                let newItem = FileItem(url: newURL, isDirectory: item.isDirectory, children: item.children, isGitIgnored: item.isGitIgnored)
                openedFiles[idx] = newItem
                if activeFileID == item.id {
                    activeFileID = newItem.id
                    selectedCodeFile = newItem
                }
                if let content = originalFileContents.removeValue(forKey: item.id) {
                    originalFileContents[newItem.id] = content
                }
                if let draft = draftFileContents.removeValue(forKey: item.id) {
                    draftFileContents[newItem.id] = draft
                }
                if unsavedFiles.remove(item.id) != nil {
                    markFileUnsavedState(fileID: newItem.id)
                }
                missingOpenFileIDs.remove(item.id)
            }
            refreshFileTree()
        } catch {
            handleError(error)
        }
    }

    func duplicateFileItem(_ item: FileItem) {
        duplicateFileItems([item])
    }

    func duplicateFileItems(_ items: [FileItem]) {
        guard !items.isEmpty else { return }
        for item in items {
            let parentURL = item.url.deletingLastPathComponent()
            let ext = item.url.pathExtension
            let baseName = ext.isEmpty ? item.name : String(item.name.dropLast(ext.count + 1))
            let newName = ext.isEmpty ? "\(baseName) copy" : "\(baseName) copy.\(ext)"
            let newURL = parentURL.appendingPathComponent(newName)
            do {
                try FileManager.default.copyItem(at: item.url, to: newURL)
            } catch { handleError(error) }
        }
        refreshFileTree()
    }

    func copyFileItem(_ item: FileItem) {
        copyFileItems([item])
    }

    func copyFileItems(_ items: [FileItem]) {
        fileBrowserClipboard = (urls: items.map(\.url), isCut: false)
    }

    func cutFileItem(_ item: FileItem) {
        cutFileItems([item])
    }

    func cutFileItems(_ items: [FileItem]) {
        fileBrowserClipboard = (urls: items.map(\.url), isCut: true)
    }

    var hasFileBrowserClipboard: Bool {
        fileBrowserClipboard != nil
    }

    func isFileInCutClipboard(_ id: String) -> Bool {
        guard let clipboard = fileBrowserClipboard, clipboard.isCut else { return false }
        return clipboard.urls.contains { $0.path == id }
    }

    func pasteFileItem(into parentURL: URL) {
        guard let clipboard = fileBrowserClipboard else { return }
        for url in clipboard.urls {
            let destURL = parentURL.appendingPathComponent(url.lastPathComponent)
            do {
                if clipboard.isCut {
                    try FileManager.default.moveItem(at: url, to: destURL)
                    let oldPath = url.path
                    if let idx = openedFiles.firstIndex(where: { $0.id == oldPath }) {
                        let newItem = FileItem(url: destURL, isDirectory: false, children: nil)
                        openedFiles[idx] = newItem
                        if activeFileID == oldPath {
                            activeFileID = newItem.id
                            selectedCodeFile = newItem
                        }
                        if let content = originalFileContents.removeValue(forKey: oldPath) {
                            originalFileContents[newItem.id] = content
                        }
                        if let draft = draftFileContents.removeValue(forKey: oldPath) {
                            draftFileContents[newItem.id] = draft
                        }
                        if unsavedFiles.remove(oldPath) != nil {
                            markFileUnsavedState(fileID: newItem.id)
                        }
                        if missingOpenFileIDs.remove(oldPath) != nil {
                            missingOpenFileIDs.insert(newItem.id)
                        }
                    }
                } else {
                    try FileManager.default.copyItem(at: url, to: destURL)
                }
            } catch {
                handleError(error)
            }
        }
        fileBrowserClipboard = nil
        refreshFileTree()
    }

    // MARK: - Flat File Helpers

    func allFlatFiles() -> [FileItem] {
        flatFileCache
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
