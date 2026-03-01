import XCTest
@testable import Zion

final class HostingModelsTests: XCTestCase {

    // MARK: - HostedPRInfo

    func testHostedPRInfoIdentifiable() {
        let pr = HostedPRInfo(
            id: 99, number: 7, title: "Add feature", state: .open,
            headBranch: "feat/new", baseBranch: "main",
            url: "https://example.com/pr/7",
            isDraft: false, author: "dev", headSHA: "abc123"
        )
        XCTAssertEqual(pr.id, 99)
        XCTAssertEqual(pr.number, 7)
        XCTAssertEqual(pr.title, "Add feature")
        XCTAssertEqual(pr.state, .open)
        XCTAssertEqual(pr.headSHA, "abc123")
    }

    func testPRStateLabels() {
        XCTAssertEqual(HostedPRInfo.PRState.open.label, "Open")
        XCTAssertEqual(HostedPRInfo.PRState.closed.label, "Closed")
        XCTAssertEqual(HostedPRInfo.PRState.merged.label, "Merged")
    }

    // MARK: - PRComment

    func testPRCommentIdentifiable() {
        let comment = PRComment(
            id: 1, author: "dev", body: "Nice work!",
            path: "src/main.swift", line: 42,
            createdAt: Date(), updatedAt: Date(),
            inReplyToID: nil
        )
        XCTAssertEqual(comment.id, 1)
        XCTAssertEqual(comment.author, "dev")
        XCTAssertEqual(comment.path, "src/main.swift")
        XCTAssertEqual(comment.line, 42)
        XCTAssertNil(comment.inReplyToID)
    }

    func testPRCommentWithReplyID() {
        let reply = PRComment(
            id: 2, author: "reviewer", body: "Fixed",
            path: "src/main.swift", line: 42,
            createdAt: Date(), updatedAt: Date(),
            inReplyToID: 1
        )
        XCTAssertEqual(reply.inReplyToID, 1)
    }

    // MARK: - PRReviewEvent

    func testPRReviewEventCases() {
        XCTAssertEqual(PRReviewEvent.allCases.count, 3)
        XCTAssertEqual(PRReviewEvent.comment.rawValue, "COMMENT")
        XCTAssertEqual(PRReviewEvent.approve.rawValue, "APPROVE")
        XCTAssertEqual(PRReviewEvent.requestChanges.rawValue, "REQUEST_CHANGES")
    }

    func testPRReviewEventLabels() {
        XCTAssertFalse(PRReviewEvent.comment.label.isEmpty)
        XCTAssertFalse(PRReviewEvent.approve.label.isEmpty)
        XCTAssertFalse(PRReviewEvent.requestChanges.label.isEmpty)
    }

    func testPRReviewEventIcons() {
        XCTAssertFalse(PRReviewEvent.comment.icon.isEmpty)
        XCTAssertFalse(PRReviewEvent.approve.icon.isEmpty)
        XCTAssertFalse(PRReviewEvent.requestChanges.icon.isEmpty)
    }

    // MARK: - PRReviewSummary

    func testPRReviewSummary() {
        let review = PRReviewSummary(
            id: 10, author: "lead", state: .approve,
            body: "LGTM", submittedAt: Date()
        )
        XCTAssertEqual(review.id, 10)
        XCTAssertEqual(review.author, "lead")
        XCTAssertEqual(review.state, .approve)
    }

    // MARK: - PRReviewDraftComment

    func testPRReviewDraftComment() {
        let draft = PRReviewDraftComment(path: "file.swift", line: 10, body: "Consider renaming")
        XCTAssertEqual(draft.path, "file.swift")
        XCTAssertEqual(draft.line, 10)
        XCTAssertEqual(draft.body, "Consider renaming")
    }

    // MARK: - HostingError

    func testHostingErrorDescriptions() {
        XCTAssertNotNil(HostingError.noToken.errorDescription)
        XCTAssertNotNil(HostingError.invalidURL.errorDescription)
        XCTAssertNotNil(HostingError.apiError("test").errorDescription)
        XCTAssertNotNil(HostingError.parseError.errorDescription)
        XCTAssertNotNil(HostingError.notSupported.errorDescription)
    }
}
