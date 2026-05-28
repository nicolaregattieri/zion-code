import XCTest
@testable import Zion

/// Phase 6.2 — pins the branch-awareness appendix wording. The
/// assistant system prompt now warns when the user is on a protected
/// default branch so the model proposes a feature branch before edits.
final class BranchAwarenessAppendixTests: XCTestCase {

    func test_emptyBranch_returnsEmptyAppendix() {
        let s = ChatService.branchAwarenessAppendixForTesting(branch: "")
        XCTAssertTrue(s.isEmpty)
    }

    func test_masterBranch_warnsAndAsksForFeatureBranch() {
        let s = ChatService.branchAwarenessAppendixForTesting(branch: "master")
        XCTAssertTrue(s.contains("`master`"))
        XCTAssertTrue(s.contains("protected default branch"))
        XCTAssertTrue(s.contains("feature branch"))
    }

    func test_mainBranch_treatedAsProtected() {
        let s = ChatService.branchAwarenessAppendixForTesting(branch: "main")
        XCTAssertTrue(s.contains("`main`"))
        XCTAssertTrue(s.contains("protected default branch"))
    }

    func test_featureBranch_passesThrough() {
        let s = ChatService.branchAwarenessAppendixForTesting(branch: "feat/auto-context")
        XCTAssertTrue(s.contains("`feat/auto-context`"))
        XCTAssertFalse(s.contains("protected default branch"),
                       "Feature branch must not surface the master/main warning")
        XCTAssertTrue(s.contains("Apply edits directly"))
    }
}
