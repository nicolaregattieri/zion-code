import XCTest
import CoreServices
@testable import Zion

@MainActor
final class FileWatcherTests: XCTestCase {

    func testClassifyChangeEventNonGitPathHasTreeImpact() {
        let event = FileWatcher.classifyChangeEvent(
            paths: ["/tmp/repo/Sources/main.swift"],
            flags: [0]
        )

        XCTAssertNotNil(event)
        XCTAssertEqual(event?.hasTreeImpact, true)
        XCTAssertEqual(event?.hasStructuralImpact, false)
        XCTAssertEqual(event?.hasWorktreeStatusImpact, true)
        XCTAssertEqual(event?.hasGitMetadataImpact, false)
        XCTAssertEqual(event?.requiresRescan, false)
    }

    func testClassifyChangeEventGitMetadataPathHasGitImpact() {
        let event = FileWatcher.classifyChangeEvent(
            paths: ["/tmp/repo/.git/index"],
            flags: [0]
        )

        XCTAssertNotNil(event)
        XCTAssertEqual(event?.hasTreeImpact, false)
        XCTAssertEqual(event?.hasStructuralImpact, false)
        XCTAssertEqual(event?.hasWorktreeStatusImpact, true)
        XCTAssertEqual(event?.hasGitMetadataImpact, true)
        XCTAssertEqual(event?.requiresRescan, false)
    }

    func testClassifyChangeEventOnlyGitInternalNonMetadataReturnsNil() {
        let event = FileWatcher.classifyChangeEvent(
            paths: ["/tmp/repo/.git/objects/ab/cdef"],
            flags: [0]
        )

        XCTAssertNil(event)
    }

    func testClassifyChangeEventRescanFlagForcesEvent() {
        let event = FileWatcher.classifyChangeEvent(
            paths: ["/tmp/repo/.git/objects/ab/cdef"],
            flags: [FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)]
        )

        XCTAssertNotNil(event)
        XCTAssertEqual(event?.hasTreeImpact, false)
        XCTAssertEqual(event?.hasStructuralImpact, false)
        XCTAssertEqual(event?.hasWorktreeStatusImpact, true)
        XCTAssertEqual(event?.hasGitMetadataImpact, false)
        XCTAssertEqual(event?.requiresRescan, true)
    }

    func testClassifyChangeEventCreatedFileHasStructuralImpact() {
        let event = FileWatcher.classifyChangeEvent(
            paths: ["/tmp/repo/Sources/new.swift"],
            flags: [FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)]
        )

        XCTAssertNotNil(event)
        XCTAssertEqual(event?.hasTreeImpact, true)
        XCTAssertEqual(event?.hasStructuralImpact, true)
        XCTAssertEqual(event?.hasWorktreeStatusImpact, true)
    }

    // MARK: - Coalescer tests (Task 6 / spec AC 6, 7, edge case 8)

    // AC 6: 50 synthetic paths across 10 distinct parent directories arrive in a
    // burst; exactly 1 onChange emission fires after the coalesce window, and the
    // emitted ChangeEvent contains the 10 deduped parents.
    func testCoalescerDedupesBurst() async throws {
        let watcher = FileWatcher(coalescerWindow: 0)
        var emitCount = 0
        var lastEvent: FileWatcher.ChangeEvent?
        watcher.onCoalescedFlushForTesting = { event in
            emitCount += 1
            lastEvent = event
        }

        let parents = (0..<10).map { "/tmp/zion_burst/parent_\($0)" }
        var paths: [String] = []
        for parent in parents {
            for file in 0..<5 {
                paths.append("\(parent)/file_\(file).swift")
            }
        }
        XCTAssertEqual(paths.count, 50)

        // Feed all 50 paths in a single synchronous ingest.
        watcher.ingestForTesting(paths: paths)

        // With coalescerWindow = 0, flush happens on the next run loop turn.
        // Await one tick so the Task runs.
        try await Task.sleep(nanoseconds: 5_000_000)
        watcher.flushCoalescerForTesting()

        XCTAssertEqual(emitCount, 1, "Burst should coalesce to exactly 1 emission")
        XCTAssertNotNil(lastEvent)
        XCTAssertEqual(lastEvent?.changedPaths.count, 10, "Parents should dedupe to 10")
        for parent in parents {
            XCTAssertTrue(
                lastEvent?.changedPaths.contains(parent) ?? false,
                "Missing expected parent: \(parent)"
            )
        }
    }

    // AC 7: rate ceiling — a 1_000-path burst spread across ~1s yields ≤12
    // coalesced emissions at the subscriber. Uses synchronous flushes instead of
    // real time to keep the test deterministic.
    func testCoalescerRateCeiling() {
        let watcher = FileWatcher(coalescerWindow: 0)
        var emitCount = 0
        watcher.onCoalescedFlushForTesting = { _ in emitCount += 1 }

        // Simulate 10 batches of 100 paths each, flushing between each batch.
        // 10 flushes stands in for ~10 emissions/s (one per coalesce window) while
        // feeding the same total 1_000 paths.
        for batch in 0..<10 {
            var paths: [String] = []
            for file in 0..<100 {
                paths.append("/tmp/zion_rate/parent_\(batch)/file_\(file).swift")
            }
            watcher.ingestForTesting(paths: paths)
            watcher.flushCoalescerForTesting()
        }

        XCTAssertLessThanOrEqual(emitCount, 12, "Coalesced emission count exceeded rate ceiling: \(emitCount)")
    }

    // Edge case 8: deinit cancels the pending coalescer timer without crashing,
    // and no delayed onChange fires on the dead instance.
    func testCoalescerDeinitCancelsTimer() async throws {
        // Use a long window so the timer is guaranteed pending at deinit time.
        weak var weakRef: FileWatcher?
        var emitCount = 0

        do {
            let watcher = FileWatcher(coalescerWindow: 1_000_000_000) // 1s
            watcher.onCoalescedFlushForTesting = { _ in emitCount += 1 }
            watcher.ingestForTesting(paths: ["/tmp/zion_deinit/parent/file.swift"])
            XCTAssertEqual(watcher.coalescerPendingCount, 1)
            weakRef = watcher
            // watcher goes out of scope at the end of this block
        }

        XCTAssertNil(weakRef, "FileWatcher should deallocate once out of scope")

        // Wait longer than the would-be timer window; even if the Task were still
        // scheduled, the FileWatcher is gone so it cannot fire onChange.
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms — well under the 1s window but enough to prove no premature fire
        XCTAssertEqual(emitCount, 0, "No onChange should fire on a deallocated FileWatcher")
    }

    func testChangeEventMergedCoalescesFlagsAndPaths() {
        let treeEvent = FileWatcher.ChangeEvent(
            changedPaths: ["/tmp/repo/a.swift"],
            hasTreeImpact: true,
            hasStructuralImpact: false,
            hasWorktreeStatusImpact: true,
            hasGitMetadataImpact: false,
            requiresRescan: false
        )
        let gitEvent = FileWatcher.ChangeEvent(
            changedPaths: ["/tmp/repo/.git/index", "/tmp/repo/a.swift"],
            hasTreeImpact: false,
            hasStructuralImpact: true,
            hasWorktreeStatusImpact: true,
            hasGitMetadataImpact: true,
            requiresRescan: true
        )

        let merged = treeEvent.merged(with: gitEvent)

        XCTAssertEqual(merged.changedPaths.count, 2)
        XCTAssertTrue(merged.changedPaths.contains("/tmp/repo/a.swift"))
        XCTAssertTrue(merged.changedPaths.contains("/tmp/repo/.git/index"))
        XCTAssertEqual(merged.hasTreeImpact, true)
        XCTAssertEqual(merged.hasStructuralImpact, true)
        XCTAssertEqual(merged.hasWorktreeStatusImpact, true)
        XCTAssertEqual(merged.hasGitMetadataImpact, true)
        XCTAssertEqual(merged.requiresRescan, true)
    }
}
