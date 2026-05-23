import XCTest
@testable import Zion

// MARK: - EditPreviewCardTests

@MainActor
final class EditPreviewCardTests: XCTestCase {

    private func makeBlock() -> EditBlock {
        EditBlock(
            path: "Sources/Foo/Bar.swift",
            search: "let x = 1",
            replace: "let x = 2"
        )
    }

    func testApplyFiresCallback() {
        var received: EditPreviewAction?
        let card = EditPreviewCard(block: makeBlock(), isStreaming: false) { received = $0 }
        card.applyTapped()
        XCTAssertEqual(received, .apply)
    }

    func testRejectFiresCallback() {
        var received: EditPreviewAction?
        let card = EditPreviewCard(block: makeBlock(), isStreaming: false) { received = $0 }
        card.rejectTapped()
        XCTAssertEqual(received, .reject)
    }

    func testEditRawFiresWithNewXML() {
        var received: EditPreviewAction?
        let card = EditPreviewCard(block: makeBlock(), isStreaming: false) { received = $0 }
        card.saveTapped("custom xml")
        XCTAssertEqual(received, .editRaw("custom xml"))
    }

    func testApplyNoOpWhileStreaming() {
        var received: EditPreviewAction?
        let card = EditPreviewCard(block: makeBlock(), isStreaming: true) { received = $0 }
        card.applyTapped()
        XCTAssertNil(received, "Apply must not fire while streaming")
    }
}

// MARK: - ApplyAllButtonTests

@MainActor
final class ApplyAllButtonTests: XCTestCase {

    private func makeBlocks(count: Int = 3) -> [EditBlock] {
        (0..<count).map { i in
            EditBlock(path: "file\(i).swift", search: "old", replace: "new")
        }
    }

    func testTapFiresOnTap() {
        var tapped = false
        let button = ApplyAllButton(
            blocks: makeBlocks(),
            isStreaming: false,
            state: .ready(3),
            onTap: { tapped = true }
        )
        button.tap()
        XCTAssertTrue(tapped)
    }

    func testTapNoOpWhileApplying() {
        var tapped = false
        let button = ApplyAllButton(
            blocks: makeBlocks(),
            isStreaming: false,
            state: .applying(2, 5),
            onTap: { tapped = true }
        )
        button.tap()
        XCTAssertFalse(tapped, "tap() must not fire while state is .applying")
    }

    func testTapNoOpWhileStreaming() {
        var tapped = false
        let button = ApplyAllButton(
            blocks: makeBlocks(),
            isStreaming: true,
            state: .ready(3),
            onTap: { tapped = true }
        )
        button.tap()
        XCTAssertFalse(tapped, "tap() must not fire while isStreaming")
    }
}
