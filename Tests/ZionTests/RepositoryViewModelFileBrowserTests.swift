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
}
