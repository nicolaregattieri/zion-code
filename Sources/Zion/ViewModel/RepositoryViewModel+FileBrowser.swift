import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension RepositoryViewModel {

    // MARK: - Zion Code Methods

    func refreshFileTree() {
        guard let url = repositoryURL else { return }
        Task {
            // Phase 1: load top-level only (instant)
            let initial = await loadFiles(at: url, ignoredPaths: nil, maxDepth: 0)

            // Phase 2: refine with gitignore — build final value before assigning
            let ignoredPaths = await loadGitIgnoredPaths()
            let files: [FileItem]
            if !ignoredPaths.isEmpty {
                cachedIgnoredPaths = ignoredPaths
                files = await loadFiles(at: url, ignoredPaths: ignoredPaths, maxDepth: 0)
            } else {
                files = initial
            }
            repositoryFiles = files  // single assignment, single cache rebuild
            reloadExpandedDirectories()
            pruneStaleSelections()
            scheduleEditorSymbolIndexRebuild(repositoryURL: url)
        }
    }

    func reloadExpandedDirectories() {
        for path in expandedPaths {
            loadChildrenIfNeeded(for: path)
        }
    }

    func loadChildrenIfNeeded(for path: String) {
        guard let item = findItem(path: path, in: repositoryFiles),
              item.isDirectory, item.children == nil else { return }
        let itemURL = item.url
        let ignoredPaths = cachedIgnoredPaths
        Task {
            let children = await loadFiles(at: itemURL, ignoredPaths: ignoredPaths, maxDepth: 0)
            repositoryFiles = updateTree(repositoryFiles, path: path, newChildren: children)
            // Breadcrumb/path navigation can request deep expansions before parent nodes
            // finish loading. Re-run pending expanded paths so deeper levels load as soon
            // as they become discoverable in the tree.
            reloadExpandedDirectories()
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

    func loadGitIgnoredPaths() async -> Set<String> {
        guard let url = repositoryURL else { return [] }
        do {
            let output = try await worker.runAction(
                args: ["ls-files", "--others", "--ignored", "--exclude-standard", "--directory"],
                in: url
            )
            let paths = output.split(separator: "\n").map {
                // git outputs paths relative to repo root, trailing / for dirs
                url.appendingPathComponent(String($0).trimmingCharacters(in: CharacterSet(charactersIn: "/"))).path
            }
            return Set(paths)
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

    func selectCodeFile(_ item: FileItem) {
        guard !item.isDirectory else { return }

        // Add to opened files if not already there
        if !openedFiles.contains(where: { $0.id == item.id }) {
            openedFiles.append(item)
        }

        activeFileID = item.id
        selectedCodeFile = item

        let itemURL = item.url
        let itemID = item.id
        Task {
            do {
                let content = try String(contentsOf: itemURL, encoding: .utf8)
                codeFileContent = content
                originalFileContents[itemID] = content
            } catch {
                codeFileContent = L10n("error.readFile", error.localizedDescription)
            }
        }
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
        if let original = originalFileContents[fileID], original != codeFileContent {
            unsavedFiles.insert(fileID)
        } else {
            unsavedFiles.remove(fileID)
        }
    }

    func closeFile(id: String) {
        guard let index = openedFiles.firstIndex(where: { $0.id == id }) else { return }

        openedFiles.remove(at: index)

        if activeFileID == id {
            if let last = openedFiles.last {
                selectCodeFile(last)
            } else {
                activeFileID = nil
                selectedCodeFile = nil
                codeFileContent = ""
            }
        }
    }

    func saveCurrentCodeFile() {
        guard let file = selectedCodeFile else { return }
        // Untitled files redirect to Save As
        if file.url.path.hasPrefix(ZionTemp.directory.path) {
            saveCurrentFileAs()
            return
        }
        var content = codeFileContent
        // Format on save (direct assignment — no undo needed since we're saving)
        if editorFormatOnSave {
            let ext = file.url.pathExtension
            if CodeFormatter.canFormat(fileExtension: ext) {
                let opts = FormatOptions(
                    tabSize: effectiveTabSize,
                    useTabs: editorUseTabs,
                    jsonSortKeys: editorJsonSortKeys
                )
                if case .success(let formatted) = CodeFormatter.format(content, fileExtension: ext, options: opts) {
                    content = formatted
                    codeFileContent = formatted
                }
            }
        }
        let fileURL = file.url
        let fileID = file.id
        let fileName = file.name
        Task {
            do {
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                statusMessage = String(format: L10n("Arquivo salvo: %@"), fileName)
                originalFileContents[fileID] = content
                unsavedFiles.remove(fileID)
                refreshRepository()
            } catch {
                handleError(error)
            }
        }
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
        let fileURL = repoURL.appendingPathComponent(relativePath)
        let item = FileItem(url: fileURL, isDirectory: false, children: nil)
        selectCodeFile(item)
        if let highlightQuery {
            let query = highlightQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty {
                editorFindSeedQuery = query
                editorFindSeedRequestID += 1
            }
        }
        navigateToCodeRequested = true
    }

    static let acceptedTextTypes: [UTType] = [
        .text, .plainText, .sourceCode, .shellScript, .script,
        .json, .xml, .yaml, .html,
    ]

    func isTextFile(_ url: URL) -> Bool {
        guard let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey]),
              let contentType = resourceValues.contentType else {
            return false
        }
        return Self.acceptedTextTypes.contains { contentType.conforms(to: $0) }
    }

    func openExternalFiles(_ urls: [URL]) {
        let fileURLs = urls.filter { !$0.hasDirectoryPath && isTextFile($0) }
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
            let item = FileItem(url: url, isDirectory: false, children: nil)
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
        codeFileContent = ""
        originalFileContents[item.id] = ""
    }

    func saveCurrentFileAs() {
        guard let file = selectedCodeFile else { return }
        let content = codeFileContent
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.name
        panel.canCreateDirectories = true
        if let repoURL = repositoryURL {
            panel.directoryURL = repoURL
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let oldID = file.id
        Task {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                let newItem = FileItem(url: url, isDirectory: false, children: nil)
                // Replace the tab
                if let idx = openedFiles.firstIndex(where: { $0.id == oldID }) {
                    openedFiles[idx] = newItem
                }
                activeFileID = newItem.id
                selectedCodeFile = newItem
                originalFileContents.removeValue(forKey: oldID)
                originalFileContents[newItem.id] = content
                unsavedFiles.remove(oldID)
                statusMessage = String(format: L10n("Arquivo salvo: %@"), newItem.name)
                refreshRepository()
            } catch {
                handleError(error)
            }
        }
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
                    closeFile(id: openedFiles[idx].id)
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
                    if let content = originalFileContents.removeValue(forKey: item.id) {
                        originalFileContents[newItem.id] = content
                    }
                    unsavedFiles.remove(item.id)
                }
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
                            if let content = originalFileContents.removeValue(forKey: oldPath) {
                                originalFileContents[newItem.id] = content
                            }
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
        editorSymbolIndexTask?.cancel()
        editorSymbolIndexTask = Task(priority: .utility) { [editorSymbolIndex] in
            await editorSymbolIndex.rebuild(repositoryURL: repositoryURL)
        }
    }

    func toggleExpansion(for path: String) {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
        } else {
            expandedPaths.insert(path)
            loadChildrenIfNeeded(for: path)
        }
    }
}
