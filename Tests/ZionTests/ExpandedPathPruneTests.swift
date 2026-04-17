import XCTest
@testable import Zion

@MainActor
final class ExpandedPathPruneTests: XCTestCase {

    private var sandbox: URL!
    private var realPaths: [String] = []

    override func setUp() async throws {
        try await super.setUp()
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)

        realPaths = []
        for i in 1...3 {
            let dir = sandbox.appendingPathComponent("real_\(i)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            realPaths.append(dir.path)
        }
    }

    override func tearDown() async throws {
        try await super.tearDown()
        try? FileManager.default.removeItem(at: sandbox)
        sandbox = nil
        realPaths = []
    }

    // AC 1: pruneExpandedPaths returns only paths that exist on disk.
    func testPruneFiltersMixedSet() async throws {
        let ghost1 = sandbox.appendingPathComponent("zion_ghost_\(UUID().uuidString)").path
        let ghost2 = sandbox.appendingPathComponent("zion_ghost_\(UUID().uuidString)").path

        var mixed = Set<String>(realPaths)
        mixed.insert(ghost1)
        mixed.insert(ghost2)

        let vm = RepositoryViewModel()
        let pruned = await vm.pruneExpandedPaths(mixed)

        XCTAssertEqual(pruned.count, 3, "Expected exactly the 3 real paths; got \(pruned)")
        for path in realPaths {
            XCTAssertTrue(pruned.contains(path), "Expected real path in result: \(path)")
        }
        XCTAssertFalse(pruned.contains(ghost1), "Ghost path should have been pruned")
        XCTAssertFalse(pruned.contains(ghost2), "Ghost path should have been pruned")
    }

    // AC 2: ghost entries are filtered out when pruneExpandedPaths is invoked
    // as the unit that backs the repo-switch restore path.
    // The restore site in RepositoryViewModel+SnapshotHelpers calls pruneExpandedPaths
    // and assigns the result back to expandedPathsByRepository[url]. This test
    // verifies that the same function, when fed a mixed set seeded into
    // expandedPathsByRepository, produces a ghost-free result.
    func testGhostEntriesPurgedOnRestore() async throws {
        let realPath = realPaths[0]
        let ghost1 = sandbox.appendingPathComponent("zion_ghost_\(UUID().uuidString)").path
        let ghost2 = sandbox.appendingPathComponent("zion_ghost_\(UUID().uuidString)").path

        let url: URL = sandbox!
        let vm = RepositoryViewModel()

        // Seed expandedPathsByRepository with ghost entries + one real entry.
        vm.expandedPathsByRepository[url] = [realPath, ghost1, ghost2]

        // Simulate the restore hook: prune and write back.
        let stored = vm.expandedPathsByRepository[url] ?? []
        let pruned = await vm.pruneExpandedPaths(stored)
        vm.expandedPathsByRepository[url] = pruned

        let result = vm.expandedPathsByRepository[url] ?? []
        XCTAssertFalse(result.contains(ghost1), "Ghost entry should be purged after restore")
        XCTAssertFalse(result.contains(ghost2), "Ghost entry should be purged after restore")
        XCTAssertTrue(result.contains(realPath), "Real path must survive restore")
        XCTAssertEqual(result.count, 1, "Only 1 real path should remain; got \(result)")
    }
}
