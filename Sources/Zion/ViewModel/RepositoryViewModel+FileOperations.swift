import Foundation
import SwiftUI

extension RepositoryViewModel {

    // MARK: - File Browser Context Menu Operations

    func refreshGitStatusAfterFileOperation() {
        refreshRepository(setBusy: false, options: .worktreeStatus, origin: .fileWatcher)
    }

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
            refreshGitStatusAfterFileOperation()
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
            refreshGitStatusAfterFileOperation()
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
            if !FileManager.default.fileExists(atPath: item.url.path) {
                if let idx = openedFiles.firstIndex(where: { $0.id == item.id }) {
                    performCloseFile(id: openedFiles[idx].id, discardDraft: true)
                }
                continue
            }
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
        refreshGitStatusAfterFileOperation()
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
        let currentName = item.name as NSString
        let selectionLength = item.isDirectory
            ? currentName.length
            : currentName.deletingPathExtension.count
        DispatchQueue.main.async {
            input.currentEditor()?.selectedRange = NSRange(location: 0, length: max(selectionLength, 0))
            input.selectText(nil)
            input.currentEditor()?.selectedRange = NSRange(location: 0, length: max(selectionLength, 0))
        }
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
            refreshGitStatusAfterFileOperation()
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
            let firstName = ext.isEmpty ? "\(baseName) copy" : "\(baseName) copy.\(ext)"
            var newURL = parentURL.appendingPathComponent(firstName)
            if FileManager.default.fileExists(atPath: newURL.path) {
                newURL = uniqueDestinationURL(for: newURL)
            }
            do {
                try FileManager.default.copyItem(at: item.url, to: newURL)
            } catch { handleError(error) }
        }
        refreshFileTree()
        refreshGitStatusAfterFileOperation()
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
            var destURL = parentURL.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: destURL.path) {
                destURL = uniqueDestinationURL(for: destURL)
            }
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
        refreshGitStatusAfterFileOperation()
    }

    // MARK: - Drag & Drop

    /// Handle a file URL drop onto a folder. Moves internal files, copies external files.
    func handleFileDrop(_ urls: [URL], into destinationFolder: URL) {
        guard let repoURL = repositoryURL else { return }
        let repoPath = repoURL.path

        // Separate internal (within repo) from external URLs
        var internalURLs: [URL] = []
        var externalURLs: [URL] = []
        for url in urls {
            if url.path.hasPrefix(repoPath) {
                internalURLs.append(url)
            } else {
                externalURLs.append(url)
            }
        }

        // If a single internal URL is part of the current selection, move all selected items
        if internalURLs.count == 1,
           let singleURL = internalURLs.first,
           selectedFileIDs.contains(singleURL.path),
           selectedFileIDs.count > 1 {
            internalURLs = selectedFileItems().map(\.url)
        }

        // Move internal files
        for url in internalURLs {
            moveFileItem(at: url, into: destinationFolder)
        }

        // Copy external files
        for url in externalURLs {
            copyExternalFile(at: url, into: destinationFolder)
        }

        if !internalURLs.isEmpty || !externalURLs.isEmpty {
            refreshFileTree()
            refreshGitStatusAfterFileOperation()
        }
    }

    /// Move a single file/folder into a destination folder, with validation and editor state migration.
    private func moveFileItem(at sourceURL: URL, into destinationFolder: URL) {
        let destPath = destinationFolder.path
        let sourcePath = sourceURL.path

        // No-op if already in that folder
        if sourceURL.deletingLastPathComponent().path == destPath { return }

        // Cannot move a folder into itself or a descendant
        if destPath.hasPrefix(sourcePath + "/") || destPath == sourcePath { return }

        var targetURL = destinationFolder.appendingPathComponent(sourceURL.lastPathComponent)

        // Handle name conflicts
        if FileManager.default.fileExists(atPath: targetURL.path) {
            targetURL = uniqueDestinationURL(for: targetURL)
        }

        do {
            try FileManager.default.moveItem(at: sourceURL, to: targetURL)
            migrateEditorState(from: sourceURL, to: targetURL)
        } catch {
            handleError(error)
        }
    }

    /// Copy an external file into a destination folder.
    private func copyExternalFile(at sourceURL: URL, into destinationFolder: URL) {
        var targetURL = destinationFolder.appendingPathComponent(sourceURL.lastPathComponent)

        if FileManager.default.fileExists(atPath: targetURL.path) {
            targetURL = uniqueDestinationURL(for: targetURL)
        }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: targetURL)
        } catch {
            handleError(error)
        }
    }

    /// Migrate editor state (opened files, drafts, unsaved state) after a file move.
    private func migrateEditorState(from oldURL: URL, to newURL: URL) {
        let oldPath = oldURL.path
        if let idx = openedFiles.firstIndex(where: { $0.id == oldPath }) {
            let newItem = FileItem(url: newURL, isDirectory: false, children: nil)
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
    }

    /// Generate a unique destination URL by appending a number suffix, matching `duplicateFileItems` pattern.
    func uniqueDestinationURL(for url: URL) -> URL {
        let parentURL = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let baseName = ext.isEmpty ? url.lastPathComponent : String(url.lastPathComponent.dropLast(ext.count + 1))
        var counter = 2
        while true {
            let candidate = ext.isEmpty
                ? parentURL.appendingPathComponent("\(baseName) \(counter)")
                : parentURL.appendingPathComponent("\(baseName) \(counter).\(ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }
}
