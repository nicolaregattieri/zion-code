import XCTest
@testable import Zion

@MainActor
final class RepositoryViewModelFileBrowserTests: XCTestCase {

    // MARK: - parseFindInFilesOutput

    func testParseFindInFilesOutputMultipleMatchesAcrossFiles() {
        let output = [
            "Sources/App.swift:10:import Foundation",
            "Sources/App.swift:25:let app = App()",
            "Tests/AppTests.swift:5:@testable import App",
        ].joined(separator: "\n")

        let results = RepositoryViewModel.parseFindInFilesOutput(output, maxMatches: 100)

        XCTAssertEqual(results.count, 2)

        // First file group
        XCTAssertEqual(results[0].file, "Sources/App.swift")
        XCTAssertEqual(results[0].matches.count, 2)
        XCTAssertEqual(results[0].matches[0].line, 10)
        XCTAssertEqual(results[0].matches[0].preview, "import Foundation")
        XCTAssertEqual(results[0].matches[1].line, 25)
        XCTAssertEqual(results[0].matches[1].preview, "let app = App()")

        // Second file group
        XCTAssertEqual(results[1].file, "Tests/AppTests.swift")
        XCTAssertEqual(results[1].matches.count, 1)
        XCTAssertEqual(results[1].matches[0].line, 5)
        XCTAssertEqual(results[1].matches[0].preview, "@testable import App")
    }

    func testParseFindInFilesOutputMaxMatchesLimit() {
        let output = [
            "a.swift:1:line one",
            "a.swift:2:line two",
            "a.swift:3:line three",
            "b.swift:1:should not appear",
        ].joined(separator: "\n")

        let results = RepositoryViewModel.parseFindInFilesOutput(output, maxMatches: 2)

        let totalMatches = results.reduce(0) { $0 + $1.matches.count }
        XCTAssertEqual(totalMatches, 2)
        XCTAssertEqual(results[0].matches[0].preview, "line one")
        XCTAssertEqual(results[0].matches[1].preview, "line two")
    }

    func testParseFindInFilesOutputEmptyInput() {
        let results = RepositoryViewModel.parseFindInFilesOutput("", maxMatches: 100)
        XCTAssertTrue(results.isEmpty)
    }

    func testParseFindInFilesOutputSingleMatch() {
        let output = "README.md:1:# Project Title"

        let results = RepositoryViewModel.parseFindInFilesOutput(output, maxMatches: 100)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].file, "README.md")
        XCTAssertEqual(results[0].matches.count, 1)
        XCTAssertEqual(results[0].matches[0].line, 1)
        XCTAssertEqual(results[0].matches[0].preview, "# Project Title")
    }

    // MARK: - isTextFile

    func testIsTextFileAcceptsDotEnv() throws {
        let vm = RepositoryViewModel()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let envFile = tempDir.appendingPathComponent(".env")
        try "API_KEY=test-value\nFEATURE_FLAG=true\n".write(to: envFile, atomically: true, encoding: .utf8)

        XCTAssertTrue(vm.isTextFile(envFile))
        XCTAssertEqual(vm.editorContentKind(for: envFile), .text)
    }

    func testIsTextFileRejectsBinaryWithoutExtension() throws {
        let vm = RepositoryViewModel()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let binaryFile = tempDir.appendingPathComponent("payload")
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: binaryFile)

        XCTAssertFalse(vm.isTextFile(binaryFile))
        XCTAssertEqual(vm.editorContentKind(for: binaryFile), .unsupported)
    }

    // MARK: - isSafeFileOrFolderName

    func testIsSafeNameValidName() {
        let vm = RepositoryViewModel()
        XCTAssertTrue(vm.isSafeFileOrFolderName("my-file.swift"))
    }

    func testIsSafeNameEmpty() {
        let vm = RepositoryViewModel()
        XCTAssertFalse(vm.isSafeFileOrFolderName(""))
    }

    func testIsSafeNameDot() {
        let vm = RepositoryViewModel()
        XCTAssertFalse(vm.isSafeFileOrFolderName("."))
    }

    func testIsSafeNameDotDot() {
        let vm = RepositoryViewModel()
        XCTAssertFalse(vm.isSafeFileOrFolderName(".."))
    }

    func testIsSafeNameForwardSlash() {
        let vm = RepositoryViewModel()
        XCTAssertFalse(vm.isSafeFileOrFolderName("path/file"))
    }

    func testIsSafeNameBackslash() {
        let vm = RepositoryViewModel()
        XCTAssertFalse(vm.isSafeFileOrFolderName("path\\file"))
    }

    func testIsSafeNameNullChar() {
        let vm = RepositoryViewModel()
        XCTAssertFalse(vm.isSafeFileOrFolderName("file\0name"))
    }

    // MARK: - isDirectChild

    func testIsDirectChildTrue() {
        let vm = RepositoryViewModel()
        let parent = URL(fileURLWithPath: "/tmp/project")
        let child = URL(fileURLWithPath: "/tmp/project/file.swift")
        XCTAssertTrue(vm.isDirectChild(child, of: parent))
    }

    func testIsDirectChildGrandchild() {
        let vm = RepositoryViewModel()
        let parent = URL(fileURLWithPath: "/tmp/project")
        let grandchild = URL(fileURLWithPath: "/tmp/project/sub/file.swift")
        // The method only checks hasPrefix(parentPath + "/"), so grandchild is also true
        XCTAssertTrue(vm.isDirectChild(grandchild, of: parent))
    }

    func testIsDirectChildSameURL() {
        let vm = RepositoryViewModel()
        let url = URL(fileURLWithPath: "/tmp/project")
        XCTAssertFalse(vm.isDirectChild(url, of: url))
    }

    func testIsDirectChildDifferentPath() {
        let vm = RepositoryViewModel()
        let parent = URL(fileURLWithPath: "/tmp/project")
        let other = URL(fileURLWithPath: "/tmp/other/file.swift")
        XCTAssertFalse(vm.isDirectChild(other, of: parent))
    }

    // MARK: - toggleFileSelection

    func testToggleFileSelectionAddsFile() {
        let vm = RepositoryViewModel()
        let item = FileItem(url: URL(fileURLWithPath: "/tmp/file.swift"), isDirectory: false, children: nil)
        vm.selectedFileIDs = []

        vm.toggleFileSelection(item)

        XCTAssertTrue(vm.selectedFileIDs.contains(item.id))
        XCTAssertEqual(vm.lastClickedFileID, item.id)
    }

    func testToggleFileSelectionRemovesFile() {
        let vm = RepositoryViewModel()
        let item = FileItem(url: URL(fileURLWithPath: "/tmp/file.swift"), isDirectory: false, children: nil)
        vm.selectedFileIDs = [item.id]

        vm.toggleFileSelection(item)

        XCTAssertFalse(vm.selectedFileIDs.contains(item.id))
        XCTAssertEqual(vm.lastClickedFileID, item.id)
    }

    // MARK: - clearFileSelection

    func testClearFileSelectionResetsState() {
        let vm = RepositoryViewModel()
        vm.selectedFileIDs = ["a", "b", "c"]
        vm.lastClickedFileID = "b"

        vm.clearFileSelection()

        XCTAssertTrue(vm.selectedFileIDs.isEmpty)
        XCTAssertNil(vm.lastClickedFileID)
    }

    // MARK: - closeFile

    func testCloseFileRemovesFromOpened() {
        let vm = RepositoryViewModel()
        let item = FileItem(url: URL(fileURLWithPath: "/tmp/file.swift"), isDirectory: false, children: nil)
        vm.openedFiles = [item]
        vm.activeFileID = "other-id" // Not the file being closed

        vm.closeFile(id: item.id)

        XCTAssertTrue(vm.openedFiles.isEmpty)
    }

    func testCloseFileActivatesLastWhenActiveFileClosed() {
        let vm = RepositoryViewModel()
        let item1 = FileItem(url: URL(fileURLWithPath: "/tmp/a.swift"), isDirectory: false, children: nil)
        let item2 = FileItem(url: URL(fileURLWithPath: "/tmp/b.swift"), isDirectory: false, children: nil)
        vm.openedFiles = [item1, item2]
        vm.activeFileID = item2.id

        vm.closeFile(id: item2.id)

        XCTAssertEqual(vm.openedFiles.count, 1)
        // After closing active, it selects last remaining
        XCTAssertEqual(vm.activeFileID, item1.id)
    }

    func testCloseLastFileClearsState() {
        let vm = RepositoryViewModel()
        let item = FileItem(url: URL(fileURLWithPath: "/tmp/file.swift"), isDirectory: false, children: nil)
        vm.openedFiles = [item]
        vm.activeFileID = item.id

        vm.closeFile(id: item.id)

        XCTAssertTrue(vm.openedFiles.isEmpty)
        XCTAssertNil(vm.activeFileID)
        XCTAssertNil(vm.selectedCodeFile)
        XCTAssertEqual(vm.codeFileContent, "")
    }

    func testCloseFileNonExistentIDDoesNothing() {
        let vm = RepositoryViewModel()
        let item = FileItem(url: URL(fileURLWithPath: "/tmp/file.swift"), isDirectory: false, children: nil)
        vm.openedFiles = [item]

        vm.closeFile(id: "non-existent")

        XCTAssertEqual(vm.openedFiles.count, 1)
    }

    func testCloseDirtyFileCancelKeepsTabOpen() async throws {
        let vm = RepositoryViewModel()
        let fileURL = try makeTempFile(ext: "swift", data: Data("let value = 1\n".utf8))
        let item = FileItem(url: fileURL, isDirectory: false, children: nil)

        vm.selectCodeFile(item)
        try await waitForEditorContent("let value = 1\n", in: vm)

        vm.codeFileContent = "let value = 2\n"
        vm.dirtyFileCloseDecisionHandler = { _ in .cancel }
        vm.closeFile(id: item.id)

        XCTAssertEqual(vm.openedFiles.map(\.id), [item.id])
        XCTAssertEqual(vm.activeFileID, item.id)
        XCTAssertEqual(vm.codeFileContent, "let value = 2\n")
        XCTAssertTrue(vm.unsavedFiles.contains(item.id))
    }

    func testCloseDirtyFileDiscardClosesAndDropsDraft() async throws {
        let vm = RepositoryViewModel()
        let fileURL = try makeTempFile(ext: "swift", data: Data("let value = 1\n".utf8))
        let item = FileItem(url: fileURL, isDirectory: false, children: nil)

        vm.selectCodeFile(item)
        try await waitForEditorContent("let value = 1\n", in: vm)

        vm.codeFileContent = "let value = 2\n"
        vm.dirtyFileCloseDecisionHandler = { _ in .discard }
        vm.closeFile(id: item.id)

        XCTAssertTrue(vm.openedFiles.isEmpty)
        XCTAssertNil(vm.activeFileID)
        XCTAssertNil(vm.selectedCodeFile)
        XCTAssertFalse(vm.unsavedFiles.contains(item.id))
        XCTAssertNil(vm.draftFileContents[item.id])
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "let value = 1\n")
    }

    func testCloseDirtyFileSaveWritesDraftBeforeClosing() async throws {
        let vm = RepositoryViewModel()
        let fileURL = try makeTempFile(ext: "swift", data: Data("let value = 1\n".utf8))
        let item = FileItem(url: fileURL, isDirectory: false, children: nil)

        vm.selectCodeFile(item)
        try await waitForEditorContent("let value = 1\n", in: vm)

        vm.codeFileContent = "let value = 2\n"
        vm.dirtyFileCloseDecisionHandler = { _ in .save }
        vm.closeFile(id: item.id)

        XCTAssertTrue(vm.openedFiles.isEmpty)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "let value = 2\n")
        XCTAssertFalse(vm.unsavedFiles.contains(item.id))
    }

    // MARK: - mergeTopLevel

    func testMergeTopLevelPreservesExistingChildren() {
        let vm = RepositoryViewModel()
        let childA = FileItem(url: URL(fileURLWithPath: "/tmp/src/a.swift"), isDirectory: false, children: nil)
        let childB = FileItem(url: URL(fileURLWithPath: "/tmp/src/b.swift"), isDirectory: false, children: nil)
        let oldSrc = FileItem(url: URL(fileURLWithPath: "/tmp/src"), isDirectory: true, children: [childA, childB])
        let oldFile = FileItem(url: URL(fileURLWithPath: "/tmp/README.md"), isDirectory: false, children: nil)

        // New scan returns same dirs but without children (flat top-level)
        let newSrc = FileItem(url: URL(fileURLWithPath: "/tmp/src"), isDirectory: true, children: nil)
        let newFile = FileItem(url: URL(fileURLWithPath: "/tmp/README.md"), isDirectory: false, children: nil)

        let merged = vm.mergeTopLevel(old: [oldSrc, oldFile], new: [newSrc, newFile])

        XCTAssertEqual(merged.count, 2)
        // Directory should keep its loaded children
        XCTAssertEqual(merged[0].children?.count, 2)
        XCTAssertEqual(merged[0].children?[0].name, "a.swift")
        // File stays unchanged
        XCTAssertNil(merged[1].children)
    }

    func testMergeTopLevelAddsNewItems() {
        let vm = RepositoryViewModel()
        let oldFile = FileItem(url: URL(fileURLWithPath: "/tmp/old.swift"), isDirectory: false, children: nil)

        let newFile = FileItem(url: URL(fileURLWithPath: "/tmp/old.swift"), isDirectory: false, children: nil)
        let addedFile = FileItem(url: URL(fileURLWithPath: "/tmp/new.swift"), isDirectory: false, children: nil)

        let merged = vm.mergeTopLevel(old: [oldFile], new: [newFile, addedFile])

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[1].name, "new.swift")
    }

    func testMergeTopLevelRemovesDeletedItems() {
        let vm = RepositoryViewModel()
        let file1 = FileItem(url: URL(fileURLWithPath: "/tmp/keep.swift"), isDirectory: false, children: nil)
        let file2 = FileItem(url: URL(fileURLWithPath: "/tmp/gone.swift"), isDirectory: false, children: nil)

        let newFile = FileItem(url: URL(fileURLWithPath: "/tmp/keep.swift"), isDirectory: false, children: nil)

        let merged = vm.mergeTopLevel(old: [file1, file2], new: [newFile])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].name, "keep.swift")
    }

    func testMergeTopLevelUpdatesGitIgnoredFlag() {
        let vm = RepositoryViewModel()
        let oldDir = FileItem(url: URL(fileURLWithPath: "/tmp/vendor"), isDirectory: true,
                              children: [FileItem(url: URL(fileURLWithPath: "/tmp/vendor/lib.js"), isDirectory: false, children: nil)],
                              isGitIgnored: false)

        let newDir = FileItem(url: URL(fileURLWithPath: "/tmp/vendor"), isDirectory: true, children: nil, isGitIgnored: true)

        let merged = vm.mergeTopLevel(old: [oldDir], new: [newDir])

        XCTAssertEqual(merged.count, 1)
        XCTAssertTrue(merged[0].isGitIgnored)
        // Children still preserved
        XCTAssertEqual(merged[0].children?.count, 1)
    }

    // MARK: - mergeDirectoryChildren

    func testMergeDirectoryChildrenPreservesLoadedDescendants() {
        let vm = RepositoryViewModel()

        let nested = FileItem(url: URL(fileURLWithPath: "/tmp/src/core/main.swift"), isDirectory: false, children: nil)
        let oldCore = FileItem(url: URL(fileURLWithPath: "/tmp/src/core"), isDirectory: true, children: [nested])
        let oldReadme = FileItem(url: URL(fileURLWithPath: "/tmp/src/README.md"), isDirectory: false, children: nil)

        let newCore = FileItem(url: URL(fileURLWithPath: "/tmp/src/core"), isDirectory: true, children: nil)
        let newReadme = FileItem(url: URL(fileURLWithPath: "/tmp/src/README.md"), isDirectory: false, children: nil)

        let merged = vm.mergeDirectoryChildren(old: [oldCore, oldReadme], new: [newCore, newReadme])

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].children?.count, 1)
        XCTAssertEqual(merged[0].children?.first?.name, "main.swift")
    }

    func testMergeDirectoryChildrenAddsNewChildrenAndRemovesDeletedOnes() {
        let vm = RepositoryViewModel()

        let oldKeep = FileItem(url: URL(fileURLWithPath: "/tmp/src/keep.swift"), isDirectory: false, children: nil)
        let oldGone = FileItem(url: URL(fileURLWithPath: "/tmp/src/gone.swift"), isDirectory: false, children: nil)
        let newKeep = FileItem(url: URL(fileURLWithPath: "/tmp/src/keep.swift"), isDirectory: false, children: nil)
        let newAdd = FileItem(url: URL(fileURLWithPath: "/tmp/src/new.swift"), isDirectory: false, children: nil)

        let merged = vm.mergeDirectoryChildren(old: [oldKeep, oldGone], new: [newKeep, newAdd])

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.map(\.name), ["keep.swift", "new.swift"])
    }

    // MARK: - loadFiles

    func testLoadFilesDoesNotHardcodeHideBuildOrToolDirectories() async throws {
        let vm = RepositoryViewModel()
        vm.showDotfiles = true
        let root = try makeTempDirectory()

        let visibleNames = ["build", "dist", "node_modules", "coverage", "vendor"]
        for name in visibleNames {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(name, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        let items = await vm.loadFiles(at: root, maxDepth: 0)

        XCTAssertEqual(Set(items.map(\.name)), Set(visibleNames))
    }

    func testLoadFilesShowsDotDirectoriesWhenHiddenFilesAreEnabled() async throws {
        let vm = RepositoryViewModel()
        vm.showDotfiles = true
        let root = try makeTempDirectory()

        let visibleNames = [".git", ".build", ".swiftpm", ".vscode", ".cache", ".DS_Store", "pkg.egg-info"]
        for name in visibleNames {
            let url = root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        let items = await vm.loadFiles(at: root, maxDepth: 0)

        XCTAssertEqual(Set(items.map(\.name)), Set(visibleNames))
    }

    func testLoadFilesHidesOnlyFilesystemHiddenEntriesWhenHiddenFilesAreDisabled() async throws {
        let vm = RepositoryViewModel()
        vm.showDotfiles = false
        let root = try makeTempDirectory()

        let hiddenNames = [".git", ".build", ".swiftpm", ".vscode", ".DS_Store"]
        let visibleNames = ["build", "dist", "node_modules", "coverage", "vendor", "pkg.egg-info"]

        for name in hiddenNames + visibleNames {
            let url = root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        let items = await vm.loadFiles(at: root, maxDepth: 0)

        XCTAssertEqual(Set(items.map(\.name)), Set(visibleNames))
    }

    // MARK: - Missing Open Files

    func testRecalculateMissingOpenFileStateMarksMissingActiveFile() throws {
        let vm = RepositoryViewModel()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let existingURL = tempDir.appendingPathComponent("exists.swift")
        let missingURL = tempDir.appendingPathComponent("missing.swift")
        try "print(\"ok\")\n".write(to: existingURL, atomically: true, encoding: .utf8)

        let existing = FileItem(url: existingURL, isDirectory: false, children: nil)
        let missing = FileItem(url: missingURL, isDirectory: false, children: nil)
        vm.openedFiles = [existing, missing]
        vm.activeFileID = missing.id
        vm.selectedCodeFile = missing
        vm.codeFileContent = "old"

        vm.recalculateMissingOpenFileState(updateEditorForActiveFile: true)

        XCTAssertTrue(vm.missingOpenFileIDs.contains(missing.id))
        XCTAssertFalse(vm.missingOpenFileIDs.contains(existing.id))
        XCTAssertEqual(vm.codeFileContent, "old")
    }

    func testRecalculateMissingOpenFileStateClearsMarkerWhenFileReturns() throws {
        let vm = RepositoryViewModel()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("transient.swift")
        let transient = FileItem(url: fileURL, isDirectory: false, children: nil)
        vm.openedFiles = [transient]
        vm.missingOpenFileIDs = [transient.id]

        try "print(\"back\")\n".write(to: fileURL, atomically: true, encoding: .utf8)
        vm.recalculateMissingOpenFileState(updateEditorForActiveFile: false)

        XCTAssertFalse(vm.missingOpenFileIDs.contains(transient.id))
    }

    // MARK: - closeOtherFiles

    func testCloseOtherFilesKeepsOnlyTarget() {
        let vm = RepositoryViewModel()
        let a = FileItem(url: URL(fileURLWithPath: "/tmp/a.swift"), isDirectory: false, children: nil)
        let b = FileItem(url: URL(fileURLWithPath: "/tmp/b.swift"), isDirectory: false, children: nil)
        let c = FileItem(url: URL(fileURLWithPath: "/tmp/c.swift"), isDirectory: false, children: nil)
        vm.openedFiles = [a, b, c]
        vm.activeFileID = b.id

        vm.closeOtherFiles(keepingID: b.id)

        XCTAssertEqual(vm.openedFiles.count, 1)
        XCTAssertEqual(vm.openedFiles[0].id, b.id)
        XCTAssertEqual(vm.activeFileID, b.id)
    }

    func testCloseOtherFilesSwitchesActiveWhenActiveRemoved() {
        let vm = RepositoryViewModel()
        let a = FileItem(url: URL(fileURLWithPath: "/tmp/a.swift"), isDirectory: false, children: nil)
        let b = FileItem(url: URL(fileURLWithPath: "/tmp/b.swift"), isDirectory: false, children: nil)
        let c = FileItem(url: URL(fileURLWithPath: "/tmp/c.swift"), isDirectory: false, children: nil)
        vm.openedFiles = [a, b, c]
        vm.activeFileID = a.id

        vm.closeOtherFiles(keepingID: b.id)

        XCTAssertEqual(vm.openedFiles.count, 1)
        XCTAssertEqual(vm.activeFileID, b.id)
    }

    // MARK: - closeFilesToTheLeft

    func testCloseFilesToTheLeftRemovesTabsBefore() {
        let vm = RepositoryViewModel()
        let a = FileItem(url: URL(fileURLWithPath: "/tmp/a.swift"), isDirectory: false, children: nil)
        let b = FileItem(url: URL(fileURLWithPath: "/tmp/b.swift"), isDirectory: false, children: nil)
        let c = FileItem(url: URL(fileURLWithPath: "/tmp/c.swift"), isDirectory: false, children: nil)
        vm.openedFiles = [a, b, c]
        vm.activeFileID = c.id

        vm.closeFilesToTheLeft(ofID: c.id)

        XCTAssertEqual(vm.openedFiles.count, 1)
        XCTAssertEqual(vm.openedFiles[0].id, c.id)
        XCTAssertEqual(vm.activeFileID, c.id)
    }

    func testCloseFilesToTheLeftSwitchesActiveWhenActiveRemoved() {
        let vm = RepositoryViewModel()
        let a = FileItem(url: URL(fileURLWithPath: "/tmp/a.swift"), isDirectory: false, children: nil)
        let b = FileItem(url: URL(fileURLWithPath: "/tmp/b.swift"), isDirectory: false, children: nil)
        let c = FileItem(url: URL(fileURLWithPath: "/tmp/c.swift"), isDirectory: false, children: nil)
        vm.openedFiles = [a, b, c]
        vm.activeFileID = a.id

        vm.closeFilesToTheLeft(ofID: c.id)

        XCTAssertEqual(vm.activeFileID, c.id)
    }

    func testCloseFilesToTheLeftNoopWhenFirst() {
        let vm = RepositoryViewModel()
        let a = FileItem(url: URL(fileURLWithPath: "/tmp/a.swift"), isDirectory: false, children: nil)
        let b = FileItem(url: URL(fileURLWithPath: "/tmp/b.swift"), isDirectory: false, children: nil)
        vm.openedFiles = [a, b]

        vm.closeFilesToTheLeft(ofID: a.id)

        XCTAssertEqual(vm.openedFiles.count, 2)
    }

    // MARK: - closeFilesToTheRight

    func testCloseFilesToTheRightRemovesTabsAfter() {
        let vm = RepositoryViewModel()
        let a = FileItem(url: URL(fileURLWithPath: "/tmp/a.swift"), isDirectory: false, children: nil)
        let b = FileItem(url: URL(fileURLWithPath: "/tmp/b.swift"), isDirectory: false, children: nil)
        let c = FileItem(url: URL(fileURLWithPath: "/tmp/c.swift"), isDirectory: false, children: nil)
        vm.openedFiles = [a, b, c]
        vm.activeFileID = a.id

        vm.closeFilesToTheRight(ofID: a.id)

        XCTAssertEqual(vm.openedFiles.count, 1)
        XCTAssertEqual(vm.openedFiles[0].id, a.id)
        XCTAssertEqual(vm.activeFileID, a.id)
    }

    func testCloseFilesToTheRightSwitchesActiveWhenActiveRemoved() {
        let vm = RepositoryViewModel()
        let a = FileItem(url: URL(fileURLWithPath: "/tmp/a.swift"), isDirectory: false, children: nil)
        let b = FileItem(url: URL(fileURLWithPath: "/tmp/b.swift"), isDirectory: false, children: nil)
        let c = FileItem(url: URL(fileURLWithPath: "/tmp/c.swift"), isDirectory: false, children: nil)
        vm.openedFiles = [a, b, c]
        vm.activeFileID = c.id

        vm.closeFilesToTheRight(ofID: a.id)

        XCTAssertEqual(vm.activeFileID, a.id)
    }

    func testCloseFilesToTheRightNoopWhenLast() {
        let vm = RepositoryViewModel()
        let a = FileItem(url: URL(fileURLWithPath: "/tmp/a.swift"), isDirectory: false, children: nil)
        let b = FileItem(url: URL(fileURLWithPath: "/tmp/b.swift"), isDirectory: false, children: nil)
        vm.openedFiles = [a, b]

        vm.closeFilesToTheRight(ofID: b.id)

        XCTAssertEqual(vm.openedFiles.count, 2)
    }

    // MARK: - closeAllFiles

    func testCloseAllFilesClearsEverything() {
        let vm = RepositoryViewModel()
        let a = FileItem(url: URL(fileURLWithPath: "/tmp/a.swift"), isDirectory: false, children: nil)
        let b = FileItem(url: URL(fileURLWithPath: "/tmp/b.swift"), isDirectory: false, children: nil)
        vm.openedFiles = [a, b]
        vm.activeFileID = a.id

        vm.closeAllFiles()

        XCTAssertTrue(vm.openedFiles.isEmpty)
        XCTAssertNil(vm.activeFileID)
        XCTAssertNil(vm.selectedCodeFile)
        XCTAssertEqual(vm.codeFileContent, "")
    }

    // MARK: - editor content kind

    func testEditorContentKindDetectsMarkdownByExtension() {
        let vm = RepositoryViewModel()
        let url = URL(fileURLWithPath: "/tmp/README.md")

        XCTAssertEqual(vm.editorContentKind(for: url), .markdown)
    }

    func testEditorContentKindDetectsImageByExtension() {
        let vm = RepositoryViewModel()
        let url = URL(fileURLWithPath: "/tmp/screenshot.png")

        XCTAssertEqual(vm.editorContentKind(for: url), .image)
    }

    func testEditorContentKindTreatsUntitledTempFilesAsText() {
        let vm = RepositoryViewModel()
        let tempURL = ZionTemp.directory.appendingPathComponent("Untitled")

        XCTAssertEqual(vm.editorContentKind(for: tempURL), .text)
    }

    func testEditorContentKindDetectsUnsupportedBinary() throws {
        let vm = RepositoryViewModel()
        let binaryURL = try makeTempFile(ext: "bin", data: Data([0x00, 0xff, 0x00, 0xff]))

        XCTAssertEqual(vm.editorContentKind(for: binaryURL), .unsupported)
    }

    func testSelectCodeFileReusesExistingTabForSameFile() throws {
        let vm = RepositoryViewModel()
        let imageURL = try makeTempFile(ext: "png", data: Data([0x89, 0x50, 0x4e, 0x47]))
        let item = FileItem(url: imageURL, isDirectory: false, children: nil)

        vm.selectCodeFile(item)
        vm.selectCodeFile(item)

        XCTAssertEqual(vm.openedFiles.count, 1)
        XCTAssertEqual(vm.activeFileID, imageURL.standardizedFileURL.path)
        XCTAssertEqual(vm.editorFocusRequestID, 2)
    }

    func testSelectCodeFileNormalizesPathToAvoidDuplicateTabs() throws {
        let vm = RepositoryViewModel()
        let imageURL = try makeTempFile(ext: "png", data: Data([0x89, 0x50, 0x4e, 0x47]))
        let alternateURL = imageURL
            .deletingLastPathComponent()
            .appendingPathComponent("sub/../\(imageURL.lastPathComponent)")

        vm.selectCodeFile(FileItem(url: imageURL, isDirectory: false, children: nil))
        vm.selectCodeFile(FileItem(url: alternateURL, isDirectory: false, children: nil))

        XCTAssertEqual(vm.openedFiles.count, 1)
        XCTAssertEqual(vm.openedFiles[0].id, imageURL.standardizedFileURL.path)
        XCTAssertEqual(vm.activeFileID, imageURL.standardizedFileURL.path)
    }

    func testSelectCodeFileImageDoesNotReadAsText() throws {
        let vm = RepositoryViewModel()
        let imageURL = try makeTempFile(ext: "png", data: Data([0x89, 0x50, 0x4e, 0x47]))
        let item = FileItem(url: imageURL, isDirectory: false, children: nil)

        vm.codeFileContent = "previous text"
        vm.selectCodeFile(item)

        XCTAssertEqual(vm.selectedEditorContentKind, .image)
        XCTAssertEqual(vm.codeFileContent, "")
        XCTAssertEqual(vm.activeFileID, item.id)
    }

    func testSelectCodeFileTextLoadsContentAsynchronously() async throws {
        let vm = RepositoryViewModel()
        let expected = "struct Fixture {}\n"
        let textURL = try makeTempFile(ext: "swift", data: Data(expected.utf8))
        let item = FileItem(url: textURL, isDirectory: false, children: nil)

        vm.selectCodeFile(item)

        XCTAssertEqual(vm.selectedEditorContentKind, .text)
        XCTAssertEqual(vm.activeFileID, item.id)

        for _ in 0..<20 where vm.codeFileContent != expected {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(vm.codeFileContent, expected)
        XCTAssertEqual(vm.originalFileContents[item.id], expected)
    }

    func testSwitchingFilesRestoresDraftForEachTab() async throws {
        let vm = RepositoryViewModel()
        let firstURL = try makeTempFile(ext: "swift", data: Data("let first = 1\n".utf8))
        let secondURL = try makeTempFile(ext: "swift", data: Data("let second = 2\n".utf8))
        let first = FileItem(url: firstURL, isDirectory: false, children: nil)
        let second = FileItem(url: secondURL, isDirectory: false, children: nil)

        vm.selectCodeFile(first)
        try await waitForEditorContent("let first = 1\n", in: vm)
        vm.codeFileContent = "let first = 10\n"

        vm.selectCodeFile(second)
        try await waitForEditorContent("let second = 2\n", in: vm)
        vm.codeFileContent = "let second = 20\n"

        vm.selectCodeFile(first)

        XCTAssertEqual(vm.codeFileContent, "let first = 10\n")
        XCTAssertTrue(vm.unsavedFiles.contains(first.id))
        XCTAssertEqual(vm.draftFileContents[first.id], "let first = 10\n")

        vm.selectCodeFile(second)

        XCTAssertEqual(vm.codeFileContent, "let second = 20\n")
        XCTAssertTrue(vm.unsavedFiles.contains(second.id))
        XCTAssertEqual(vm.draftFileContents[second.id], "let second = 20\n")
    }

    func testSaveCurrentCodeFileDoesNotOverwriteImageData() throws {
        let vm = RepositoryViewModel()
        let original = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a])
        let imageURL = try makeTempFile(ext: "png", data: original)
        let item = FileItem(url: imageURL, isDirectory: false, children: nil)

        vm.selectCodeFile(item)
        vm.codeFileContent = "this should never be written"
        vm.saveCurrentCodeFile()

        let resulting = try Data(contentsOf: imageURL)
        XCTAssertEqual(resulting, original)
        XCTAssertEqual(vm.statusMessage, L10n("editor.file.readOnlyBinary"))
    }

    func testSaveCurrentFileAsDoesNotAllowBinaryEditorPath() throws {
        let vm = RepositoryViewModel()
        let imageURL = try makeTempFile(ext: "png", data: Data([0x89, 0x50, 0x4e, 0x47]))
        let item = FileItem(url: imageURL, isDirectory: false, children: nil)
        vm.selectCodeFile(item)

        vm.saveCurrentFileAs()

        XCTAssertEqual(vm.statusMessage, L10n("editor.file.readOnlyBinary"))
    }

    func testOpenExternalFilesAcceptsImageFiles() throws {
        let vm = RepositoryViewModel()
        let imageURL = try makeTempFile(ext: "png", data: Data([0x89, 0x50, 0x4e, 0x47]))

        vm.openExternalFiles([imageURL])

        XCTAssertEqual(vm.selectedCodeFile?.id, imageURL.path)
        XCTAssertEqual(vm.selectedEditorContentKind, .image)
        XCTAssertTrue(vm.openedFiles.contains(where: { $0.id == imageURL.path }))
    }

    func testOpenExternalFilesSkipsUnsupportedBinaryFiles() throws {
        let vm = RepositoryViewModel()
        let binaryURL = try makeTempFile(ext: "bin", data: Data([0x00, 0xff, 0x00, 0xff]))

        vm.openExternalFiles([binaryURL])

        XCTAssertTrue(vm.openedFiles.isEmpty)
        XCTAssertNil(vm.selectedCodeFile)
    }

    private func makeTempFile(ext: String, data: Data) throws -> URL {
        let directory = try makeTempDirectory()
        let fileURL = directory.appendingPathComponent("fixture.\(ext)")
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private func makeTempDirectory() throws -> URL {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = tempRoot.appendingPathComponent("zion-filebrowser-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func waitForEditorContent(_ expected: String, in vm: RepositoryViewModel) async throws {
        for _ in 0..<20 where vm.codeFileContent != expected {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(vm.codeFileContent, expected)
    }
}
