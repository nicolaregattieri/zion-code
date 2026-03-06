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
        XCTAssertEqual(event?.hasGitMetadataImpact, false)
        XCTAssertEqual(event?.requiresRescan, true)
    }

    func testChangeEventMergedCoalescesFlagsAndPaths() {
        let treeEvent = FileWatcher.ChangeEvent(
            changedPaths: ["/tmp/repo/a.swift"],
            hasTreeImpact: true,
            hasGitMetadataImpact: false,
            requiresRescan: false
        )
        let gitEvent = FileWatcher.ChangeEvent(
            changedPaths: ["/tmp/repo/.git/index", "/tmp/repo/a.swift"],
            hasTreeImpact: false,
            hasGitMetadataImpact: true,
            requiresRescan: true
        )

        let merged = treeEvent.merged(with: gitEvent)

        XCTAssertEqual(merged.changedPaths.count, 2)
        XCTAssertTrue(merged.changedPaths.contains("/tmp/repo/a.swift"))
        XCTAssertTrue(merged.changedPaths.contains("/tmp/repo/.git/index"))
        XCTAssertEqual(merged.hasTreeImpact, true)
        XCTAssertEqual(merged.hasGitMetadataImpact, true)
        XCTAssertEqual(merged.requiresRescan, true)
    }
}
