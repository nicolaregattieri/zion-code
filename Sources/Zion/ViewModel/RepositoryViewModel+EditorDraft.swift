import Foundation
import SwiftUI

extension RepositoryViewModel {

    // MARK: - Editor Draft & Unsaved State

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

        // If the file has no unsaved edits, check whether the disk version
        // changed while this tab was in the background (e.g. stash pop,
        // branch switch, external editor).  When it did, reload from disk
        // so the editor never shows stale content.
        if !unsavedFiles.contains(item.id),
           let diskContent = try? String(contentsOf: item.url, encoding: .utf8),
           diskContent != originalFileContents[item.id] {
            originalFileContents[item.id] = diskContent
            draftFileContents[item.id] = diskContent
            applyEditorContent(diskContent)
            unsavedFiles.remove(item.id)
            return true
        }

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
}
