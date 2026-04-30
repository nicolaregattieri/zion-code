import Foundation
import SwiftUI

extension RepositoryViewModel {

    // MARK: - Editor File Open / Close / Activation

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

    func prepareFileForClosing(_ item: FileItem) -> EditorFileClosePreparation {
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
            if let draftContent = draftFileContents[activeItem.id] {
                if let detected = IndentationDetector.detect(in: draftContent) {
                    fileDetectedTabSize = detected.tabSize
                    fileDetectedUseTabs = detected.useTabs
                } else {
                    fileDetectedTabSize = nil
                    fileDetectedUseTabs = nil
                }
            }
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
                    if let detected = IndentationDetector.detect(in: resolvedContent) {
                        fileDetectedTabSize = detected.tabSize
                        fileDetectedUseTabs = detected.useTabs
                    } else {
                        fileDetectedTabSize = nil
                        fileDetectedUseTabs = nil
                    }
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

    // MARK: - File Save/Edit Commands

    func saveEditorFile(_ file: FileItem) -> EditorFileSaveResult {
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

    func saveEditorFileAs(_ file: FileItem, content: String? = nil) -> EditorFileSaveResult {
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
        let ext = editorFileExtension(for: file.url)
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

    func editorFileExtension(for url: URL) -> String {
        EditorFileInspector.editorFileExtension(for: url)
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
        // RT-006: Normalize first so URLs containing `/./`, trailing dots,
        // or unresolved symlinks don't surface as a repo root with
        // `lastPathComponent == "."`, which then makes downstream URL
        // equality / stash-key lookups miss the already-open repo.
        let normalized = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        var current = normalized.deletingLastPathComponent()
        while current.path != "/" {
            let gitDir = current.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: gitDir.path) {
                return current.standardizedFileURL.resolvingSymlinksInPath()
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
}
