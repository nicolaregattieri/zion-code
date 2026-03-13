import XCTest
@testable import Zion

final class FindInFilesViewLogicTests: XCTestCase {
    private func makeMatches() -> [FindInFilesMatch] {
        [
            FindInFilesMatch(file: "Sources/App.swift", line: 10, preview: "first"),
            FindInFilesMatch(file: "Sources/App.swift", line: 20, preview: "second"),
            FindInFilesMatch(file: "Tests/AppTests.swift", line: 5, preview: "third")
        ]
    }

    private func makeResults() -> [FindInFilesFileResult] {
        [
            FindInFilesFileResult(
                file: "Sources/App.swift",
                matches: [
                    FindInFilesMatch(file: "Sources/App.swift", line: 10, preview: "first"),
                    FindInFilesMatch(file: "Sources/App.swift", line: 20, preview: "second")
                ]
            ),
            FindInFilesFileResult(
                file: "Tests/AppTests.swift",
                matches: [
                    FindInFilesMatch(file: "Tests/AppTests.swift", line: 5, preview: "third")
                ]
            )
        ]
    }

    func testShouldApplySearchResultsRequiresLatestAndNotCancelled() {
        XCTAssertTrue(
            FindInFilesViewLogic.shouldApplySearchResults(
                requestID: 5,
                latestRequestID: 5,
                isCancelled: false
            )
        )

        XCTAssertFalse(
            FindInFilesViewLogic.shouldApplySearchResults(
                requestID: 4,
                latestRequestID: 5,
                isCancelled: false
            )
        )

        XCTAssertFalse(
            FindInFilesViewLogic.shouldApplySearchResults(
                requestID: 5,
                latestRequestID: 5,
                isCancelled: true
            )
        )
    }

    func testPreferredSelectedMatchIDKeepsCurrentWhenPresent() {
        let matches = makeMatches()
        let currentID = matches[1].id

        let selected = FindInFilesViewLogic.preferredSelectedMatchID(
            currentSelectedID: currentID,
            matches: matches
        )

        XCTAssertEqual(selected, currentID)
    }

    func testPreferredSelectedMatchIDFallsBackToFirstWhenCurrentMissing() {
        let matches = makeMatches()

        let selected = FindInFilesViewLogic.preferredSelectedMatchID(
            currentSelectedID: "missing:1",
            matches: matches
        )

        XCTAssertEqual(selected, matches.first?.id)
    }

    func testPreferredSelectedMatchIDReturnsNilForEmptyMatches() {
        let selected = FindInFilesViewLogic.preferredSelectedMatchID(
            currentSelectedID: nil,
            matches: []
        )

        XCTAssertNil(selected)
    }

    func testNextMatchReturnsFirstWhenNoSelectionAndForward() {
        let matches = makeMatches()

        let next = FindInFilesViewLogic.nextMatch(
            matches: matches,
            currentSelectedID: nil,
            direction: 1
        )

        XCTAssertEqual(next?.id, matches[0].id)
    }

    func testNextMatchReturnsLastWhenNoSelectionAndBackward() {
        let matches = makeMatches()

        let next = FindInFilesViewLogic.nextMatch(
            matches: matches,
            currentSelectedID: nil,
            direction: -1
        )

        XCTAssertEqual(next?.id, matches[2].id)
    }

    func testNextMatchWrapsForwardFromLastToFirst() {
        let matches = makeMatches()

        let next = FindInFilesViewLogic.nextMatch(
            matches: matches,
            currentSelectedID: matches[2].id,
            direction: 1
        )

        XCTAssertEqual(next?.id, matches[0].id)
    }

    func testNextMatchWrapsBackwardFromFirstToLast() {
        let matches = makeMatches()

        let next = FindInFilesViewLogic.nextMatch(
            matches: matches,
            currentSelectedID: matches[0].id,
            direction: -1
        )

        XCTAssertEqual(next?.id, matches[2].id)
    }

    func testNextMatchReturnsNilForEmptyMatches() {
        let next = FindInFilesViewLogic.nextMatch(
            matches: [],
            currentSelectedID: nil,
            direction: 1
        )

        XCTAssertNil(next)
    }

    func testDefaultExpandedFilesAutoExpandsSmallResultSets() {
        let expanded = FindInFilesViewLogic.defaultExpandedFiles(
            results: makeResults(),
            maxAutoExpandedFiles: 10,
            maxAutoExpandedMatches: 10
        )

        XCTAssertEqual(expanded, Set(["Sources/App.swift", "Tests/AppTests.swift"]))
    }

    func testDefaultExpandedFilesKeepsLargeMatchSetsCollapsed() {
        let largeResults = [
            FindInFilesFileResult(
                file: "Sources/App.swift",
                matches: (1...120).map { FindInFilesMatch(file: "Sources/App.swift", line: $0, preview: "match-\($0)") }
            ),
            FindInFilesFileResult(
                file: "Tests/AppTests.swift",
                matches: (1...120).map { FindInFilesMatch(file: "Tests/AppTests.swift", line: $0, preview: "match-\($0)") }
            )
        ]

        let expanded = FindInFilesViewLogic.defaultExpandedFiles(
            results: largeResults,
            maxAutoExpandedFiles: 10,
            maxAutoExpandedMatches: 60
        )

        XCTAssertTrue(expanded.isEmpty)
    }

    func testEffectiveVisibleMatchesRespectsRevealCount() {
        let matches = (1...100).map { FindInFilesMatch(file: "Sources/App.swift", line: $0, preview: "match-\($0)") }

        let visible = FindInFilesViewLogic.effectiveVisibleMatches(
            matches: matches,
            revealedCount: 40,
            selectedMatchID: nil,
            defaultVisibleCount: 20
        )

        XCTAssertEqual(visible.count, 40)
        XCTAssertEqual(visible.last?.line, 40)
    }

    func testEffectiveVisibleMatchesIncludesSelectedMatchOutsideCurrentPage() {
        let matches = (1...100).map { FindInFilesMatch(file: "Sources/App.swift", line: $0, preview: "match-\($0)") }

        let visible = FindInFilesViewLogic.effectiveVisibleMatches(
            matches: matches,
            revealedCount: 40,
            selectedMatchID: matches[74].id,
            defaultVisibleCount: 20
        )

        XCTAssertEqual(visible.count, 75)
        XCTAssertEqual(visible.last?.id, matches[74].id)
    }

    func testRemainingMatchCountReturnsPositiveRemainder() {
        XCTAssertEqual(
            FindInFilesViewLogic.remainingMatchCount(totalMatches: 120, visibleMatches: 40),
            80
        )
    }
}
