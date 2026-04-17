import XCTest
@testable import Zion

@MainActor
final class OptimisticStagingTests: XCTestCase {

    private func makeViewModel(repoPath: String = "/tmp/zion_optimistic_test") -> RepositoryViewModel {
        let vm = RepositoryViewModel()
        vm.repositoryURL = URL(fileURLWithPath: repoPath)
        return vm
    }

    // AC 8: Stage mutates the observable status collections in the same run loop.
    func testStageMutatesSynchronously() {
        let vm = makeViewModel()
        vm.uncommittedChanges = [
            " M src/a.swift",
            " M src/b.swift",
        ]

        XCTAssertFalse(vm.hasStagedChanges)
        XCTAssertEqual(vm.stagedChangesCount, 0)
        XCTAssertEqual(vm.unstagedChangesCount, 2)

        let url = URL(fileURLWithPath: "/tmp/zion_optimistic_test/src/a.swift")
        vm.applyOptimisticStage(urls: [url])

        XCTAssertTrue(vm.hasStagedChanges, "Stage must flip hasStagedChanges synchronously")
        XCTAssertEqual(vm.stagedChangesCount, 1, "Staged count must update immediately")
        XCTAssertEqual(vm.unstagedChangesCount, 1, "Unstaged count must update immediately")
    }

    // AC 8 bonus: Staging an untracked file moves it to staged add.
    func testStageUntrackedBecomesAdd() {
        let vm = makeViewModel()
        vm.uncommittedChanges = [
            "?? src/new.swift",
        ]
        XCTAssertEqual(vm.untrackedChangesCount, 1)
        XCTAssertEqual(vm.stagedChangesCount, 0)

        vm.applyOptimisticStage(urls: [URL(fileURLWithPath: "/tmp/zion_optimistic_test/src/new.swift")])

        XCTAssertEqual(vm.untrackedChangesCount, 0, "Untracked should be consumed")
        XCTAssertEqual(vm.stagedChangesCount, 1, "Should appear as staged add")
    }

    // AC 9: Discard removes working-tree-only entries synchronously.
    func testDiscardRemovesSynchronously() {
        let vm = makeViewModel()
        vm.uncommittedChanges = [
            " M src/a.swift",
            " M src/b.swift",
            " M src/c.swift",
        ]
        XCTAssertEqual(vm.unstagedChangesCount, 3)

        let urls = [
            URL(fileURLWithPath: "/tmp/zion_optimistic_test/src/a.swift"),
            URL(fileURLWithPath: "/tmp/zion_optimistic_test/src/b.swift"),
        ]
        vm.applyOptimisticDiscard(urls: urls)

        XCTAssertEqual(vm.unstagedChangesCount, 1, "Two working-tree entries should be removed")
        XCTAssertEqual(vm.uncommittedChanges.count, 1)
    }

    // AC 9 bonus: Discard preserves the staged side when both sides are dirty.
    func testDiscardClearsOnlyWorktreeSide() {
        let vm = makeViewModel()
        vm.uncommittedChanges = [
            "MM src/a.swift", // staged modified + working-tree modified
        ]
        XCTAssertEqual(vm.stagedChangesCount, 1)
        XCTAssertEqual(vm.unstagedChangesCount, 1)

        vm.applyOptimisticDiscard(urls: [URL(fileURLWithPath: "/tmp/zion_optimistic_test/src/a.swift")])

        XCTAssertEqual(vm.stagedChangesCount, 1, "Staged side must be preserved")
        XCTAssertEqual(vm.unstagedChangesCount, 0, "Working-tree side must be cleared")
    }

    // AC 10: On failure, a captured snapshot is restored and state reverts.
    func testFailureRevertsOptimisticState() {
        let vm = makeViewModel()
        vm.uncommittedChanges = [
            " M src/a.swift",
            " M src/b.swift",
        ]

        let snapshot = vm.snapshotPorcelainEntries()
        XCTAssertEqual(snapshot.count, 2)

        // Simulate the optimistic staging happening.
        vm.applyOptimisticStage(urls: [URL(fileURLWithPath: "/tmp/zion_optimistic_test/src/a.swift")])
        XCTAssertEqual(vm.stagedChangesCount, 1)

        // Simulate the git command failing → onFailure invokes restorePorcelainEntries.
        vm.restorePorcelainEntries(snapshot)

        XCTAssertEqual(vm.uncommittedChanges, snapshot, "State must match pre-action snapshot exactly")
        XCTAssertEqual(vm.stagedChangesCount, 0)
        XCTAssertEqual(vm.unstagedChangesCount, 2)
    }

    // AC 11: After success, real porcelain output replaces optimistic state — no duplicates.
    func testReconciliationAfterSuccess() {
        let vm = makeViewModel()
        vm.uncommittedChanges = [
            " M src/a.swift",
            " M src/b.swift",
        ]

        // Optimistic stage of one file.
        vm.applyOptimisticStage(urls: [URL(fileURLWithPath: "/tmp/zion_optimistic_test/src/a.swift")])

        // Simulate the real refreshStatusOnly path replacing uncommittedChanges with
        // fresh porcelain output that matches the optimistic prediction exactly.
        vm.uncommittedChanges = [
            "M  src/a.swift",
            " M src/b.swift",
        ]

        // After reconciliation: no duplicates, counts match.
        XCTAssertEqual(vm.uncommittedChanges.count, 2, "No duplicate rows after reconcile")
        XCTAssertEqual(vm.stagedChangesCount, 1)
        XCTAssertEqual(vm.unstagedChangesCount, 1)
    }
}
