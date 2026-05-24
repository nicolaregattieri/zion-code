// MultiFileDiffSummaryTests.swift — behavior tests for the MultiFileDiffSummary state model.
// View rendering is exercised by manual UI verification per AC-K.

import XCTest
@testable import Zion

@MainActor
final class MultiFileDiffSummaryTests: XCTestCase {

    // MARK: - Helpers

    private func makeBlocks(count: Int) -> [EditBlock] {
        (0..<count).map { i in
            EditBlock(
                path: "Sources/File\(i).swift",
                search: "old",
                replace: "new"
            )
        }
    }

    // MARK: - Render thresholds

    func test_single_change_does_not_render() {
        let state = MultiFileDiffSummaryState(blocks: makeBlocks(count: 1))
        XCTAssertFalse(state.shouldRender)
    }

    func test_two_changes_render() {
        let state = MultiFileDiffSummaryState(blocks: makeBlocks(count: 2))
        XCTAssertTrue(state.shouldRender)
    }

    func test_three_changes_render() {
        let state = MultiFileDiffSummaryState(blocks: makeBlocks(count: 3))
        XCTAssertTrue(state.shouldRender)
    }

    // MARK: - Approve all in order

    func test_approve_all_calls_apply_in_order() {
        let blocks = makeBlocks(count: 3)
        let state = MultiFileDiffSummaryState(blocks: blocks)
        var observed: [String] = []
        state.approveAll { block in
            observed.append(block.path)
        }
        XCTAssertEqual(observed, blocks.map { $0.path })
    }

    // MARK: - Reject all

    func test_reject_all_calls_cancel() {
        let blocks = makeBlocks(count: 3)
        let state = MultiFileDiffSummaryState(blocks: blocks)
        var rejectedCount = 0
        state.rejectAll { rejectedCount += 1 }
        XCTAssertEqual(rejectedCount, 1)
    }

    // MARK: - Collapse threshold

    func test_collapse_threshold_at_four() {
        let state = MultiFileDiffSummaryState(blocks: makeBlocks(count: 4))
        XCTAssertTrue(state.collapsedRendering)
    }

    func test_collapse_threshold_inverse_at_three() {
        let state = MultiFileDiffSummaryState(blocks: makeBlocks(count: 3))
        XCTAssertFalse(state.collapsedRendering)
    }

    // MARK: - Localization key contract

    func test_header_key_is_registered_for_l10n() {
        let state = MultiFileDiffSummaryState(blocks: makeBlocks(count: 2))
        XCTAssertEqual(state.headerKey, "chat.multifileDiff.header")
    }
}
