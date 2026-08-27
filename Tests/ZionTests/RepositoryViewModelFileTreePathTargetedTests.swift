import XCTest
@testable import Zion

@MainActor
final class RepositoryViewModelFileTreePathTargetedTests: XCTestCase {

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.standardizedFileURL
    }

    private func waitForCondition(
        timeout: TimeInterval = 2.0,
        interval: UInt64 = 30_000_000,
        _ check: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if check() { return }
            try? await Task.sleep(nanoseconds: interval)
        }
    }

    // A file dropped inside a folder that the user has never opened should
    // load that folder's children silently (so the file is in memory the
    // moment the user clicks to expand). The folder must NOT be auto-added
    // to `expandedPaths` — that heuristic was removed because it misfired
    // for every unopened folder (`.git`, `build`, `dist`).
    func testEnsureChildrenLoadedReloadsUnopenedFolderWithoutExpanding() async throws {
        let vm = RepositoryViewModel()
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let newFolder = tempDir.appendingPathComponent("newFolder", isDirectory: true)
        try FileManager.default.createDirectory(at: newFolder, withIntermediateDirectories: true)
        let newFile = newFolder.appendingPathComponent("newFile.swift")
        try "import Foundation\n".write(to: newFile, atomically: true, encoding: .utf8)

        vm.repositoryURL = tempDir
        // Simulate the state that follows `runFileTreeRefresh`'s top-level
        // walk: the folder is in `repositoryFiles` but its children have
        // not been loaded yet (would normally only happen on user click).
        let folderItem = FileItem(url: newFolder, isDirectory: true, children: nil)
        vm.repositoryFiles = [folderItem]
        XCTAssertFalse(vm.expandedPaths.contains(newFolder.path))

        vm.ensureChildrenLoadedForChangedPaths([newFile.path])

        // Folder stays collapsed.
        XCTAssertFalse(vm.expandedPaths.contains(newFolder.path),
                       "Unopened folder must not be auto-added to expandedPaths")
        // Children load asynchronously so the file shows on first click.
        await waitForCondition {
            guard let folder = vm.findItem(path: newFolder.path, in: vm.repositoryFiles) else {
                return false
            }
            return folder.children?.contains(where: { $0.url.lastPathComponent == "newFile.swift" }) ?? false
        }
        let folderAfter = vm.findItem(path: newFolder.path, in: vm.repositoryFiles)
        XCTAssertNotNil(folderAfter?.children, "Children should load asynchronously")
        XCTAssertTrue(folderAfter?.children?.contains(where: { $0.url.lastPathComponent == "newFile.swift" }) ?? false,
                      "newFile.swift should be loaded into the folder's children for instant click reveal")
    }

    // `FileWatcher.coalesceEvent` collapses incoming file paths into their
    // parent directory before forwarding to `ensureChildrenLoadedForChangedPaths`.
    // So the function may be invoked with the parent directory itself as the
    // `changed` path (NOT the new file path). Walk must start at the changed
    // path so that directory gets reloaded — previously the walk started at
    // its parent and only reached the repo root, which was skipped, so the
    // new file never surfaced in an already-expanded folder.
    func testEnsureChildrenLoadedReloadsCoalescedParentDirectory() async throws {
        let vm = RepositoryViewModel()
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folder = tempDir.appendingPathComponent("postman", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let oldFile = folder.appendingPathComponent("a.json")
        try "{}\n".write(to: oldFile, atomically: true, encoding: .utf8)

        vm.repositoryURL = tempDir
        let oldChild = FileItem(url: oldFile, isDirectory: false, children: nil)
        let folderItem = FileItem(url: folder, isDirectory: true, children: [oldChild])
        vm.repositoryFiles = [folderItem]
        vm.expandedPaths.insert(folder.path)

        // External actor drops a new file inside the (already-expanded) folder.
        let newFile = folder.appendingPathComponent("b.json")
        try "{}\n".write(to: newFile, atomically: true, encoding: .utf8)

        // Coalesced event: the watcher reports the PARENT directory, not the
        // file. This is the production path.
        vm.ensureChildrenLoadedForChangedPaths([folder.path])

        await waitForCondition {
            guard let f = vm.findItem(path: folder.path, in: vm.repositoryFiles) else { return false }
            return f.children?.contains(where: { $0.url.lastPathComponent == "b.json" }) ?? false
        }
        let folderAfter = vm.findItem(path: folder.path, in: vm.repositoryFiles)
        XCTAssertTrue(folderAfter?.children?.contains(where: { $0.url.lastPathComponent == "b.json" }) ?? false,
                      "b.json should appear after a coalesced parent-directory event")
    }

    // Existing folder that is already collapsed (children already loaded
    // earlier, then subsequent file added externally) should NOT be
    // auto-expanded — but children should be force-reloaded so the new file
    // is in memory and shows the moment the user clicks to expand.
    func testEnsureChildrenLoadedReloadsExistingCollapsedFolderWithoutExpanding() async throws {
        let vm = RepositoryViewModel()
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folder = tempDir.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let oldFile = folder.appendingPathComponent("Old.swift")
        try "old\n".write(to: oldFile, atomically: true, encoding: .utf8)

        vm.repositoryURL = tempDir
        // Simulate prior load: folder has children populated (Old.swift).
        let oldChild = FileItem(url: oldFile, isDirectory: false, children: nil)
        let folderItem = FileItem(url: folder, isDirectory: true, children: [oldChild])
        vm.repositoryFiles = [folderItem]
        // Folder is collapsed (not in expandedPaths).
        XCTAssertFalse(vm.expandedPaths.contains(folder.path))

        // External actor drops a new file inside the (still-collapsed) folder.
        let newFile = folder.appendingPathComponent("New.swift")
        try "new\n".write(to: newFile, atomically: true, encoding: .utf8)

        vm.ensureChildrenLoadedForChangedPaths([newFile.path])

        // Existing collapsed folder should stay collapsed.
        XCTAssertFalse(vm.expandedPaths.contains(folder.path),
                       "Pre-existing collapsed folder should not be auto-expanded")
        // But its children should refresh asynchronously to include New.swift.
        await waitForCondition {
            guard let f = vm.findItem(path: folder.path, in: vm.repositoryFiles) else { return false }
            return f.children?.contains(where: { $0.url.lastPathComponent == "New.swift" }) ?? false
        }
        let folderAfter = vm.findItem(path: folder.path, in: vm.repositoryFiles)
        XCTAssertTrue(folderAfter?.children?.contains(where: { $0.url.lastPathComponent == "New.swift" }) ?? false,
                      "New.swift should be loaded into the collapsed folder's children for instant click reveal")
    }

    // Regression: an AI CLI (claude, codex) creates a whole NEW folder tree
    // like `newpkg/lib/foo.swift`. `newpkg` doesn't exist in `repositoryFiles`
    // yet. Previously `ensureChildrenLoadedForChangedPaths` walked ancestors
    // and called `loadChildrenIfNeeded(newpkg)` — which no-ops (findItem is
    // nil) — so the folder never surfaced until the next top-level refresh
    // AND `refreshFileTree`'s maxDepth-0 walk added `newpkg` but left its
    // children nil, hiding `lib/foo.swift`. Fix: walk up to the nearest
    // existing ancestor (here: the repo root's direct child that DOES exist,
    // or the caller of this method — which is followed by refreshFileTree
    // adding newpkg — so we re-force-reload newpkg on the next tick).
    func testEnsureChildrenLoadedSurfacesFreshlyCreatedTopLevelFolder() async throws {
        let vm = RepositoryViewModel()
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        vm.repositoryURL = tempDir
        // Simulate the state right after a top-level refreshFileTree walk:
        // the new top-level folder DOES exist in repositoryFiles (with nil
        // children) — this is the realistic state because refreshFileTree
        // and ensureChildrenLoadedForChangedPaths run back-to-back.
        let newPkg = tempDir.appendingPathComponent("newpkg", isDirectory: true)
        let libDir = newPkg.appendingPathComponent("lib", isDirectory: true)
        try FileManager.default.createDirectory(at: libDir, withIntermediateDirectories: true)
        let deepFile = libDir.appendingPathComponent("foo.swift")
        try "let x = 1\n".write(to: deepFile, atomically: true, encoding: .utf8)

        vm.repositoryFiles = [FileItem(url: newPkg, isDirectory: true, children: nil)]

        // FSEvent coalesces to the parent dir of the created file.
        vm.ensureChildrenLoadedForChangedPaths([libDir.path])

        // newpkg should get its children loaded so lib/ is discoverable.
        await waitForCondition(timeout: 3.0) {
            guard let pkg = vm.findItem(path: newPkg.path, in: vm.repositoryFiles) else { return false }
            return pkg.children?.contains(where: { $0.url.lastPathComponent == "lib" }) ?? false
        }
        let pkgAfter = vm.findItem(path: newPkg.path, in: vm.repositoryFiles)
        XCTAssertTrue(pkgAfter?.children?.contains(where: { $0.url.lastPathComponent == "lib" }) ?? false,
                      "newpkg should have 'lib' in its children after ensureChildrenLoaded walks up to the nearest existing ancestor")
    }

    // Paths outside the repository must be ignored — no expandedPaths
    // mutation, no I/O.
    func testEnsureChildrenLoadedIgnoresPathsOutsideRepository() async throws {
        let vm = RepositoryViewModel()
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let outsideDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: outsideDir) }

        vm.repositoryURL = tempDir
        vm.repositoryFiles = []

        let foreignPath = outsideDir.appendingPathComponent("foreign.txt").path
        vm.ensureChildrenLoadedForChangedPaths([foreignPath])

        XCTAssertTrue(vm.expandedPaths.isEmpty,
                      "Paths outside the repository must not mutate expandedPaths")
    }
}
