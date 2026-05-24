import XCTest
@testable import Zion

final class ApprovalPolicyEnforcementTests: XCTestCase {

    func test_manual_asks_destructive() {
        XCTAssertTrue(ApprovalPolicy.manual.asksDestructive)
    }

    func test_autoSafe_asks_destructive() {
        XCTAssertTrue(ApprovalPolicy.autoSafe.asksDestructive)
    }

    func test_auto_does_not_ask() {
        XCTAssertFalse(ApprovalPolicy.auto.asksDestructive)
    }

    func test_yolo_does_not_ask() {
        XCTAssertFalse(ApprovalPolicy.yolo.asksDestructive)
    }

    func test_yolo_grants_fullAccess_bash_tier() {
        XCTAssertEqual(ApprovalPolicy.yolo.bashTier, .fullAccess)
    }

    func test_manual_uses_planFirst() {
        XCTAssertEqual(ApprovalPolicy.manual.planMode, .planFirst)
    }

    // Additional coverage

    func test_autoSafe_uses_autoApply_plan_mode() {
        XCTAssertEqual(ApprovalPolicy.autoSafe.planMode, .autoApply)
    }

    func test_manual_does_not_autoCommit() {
        XCTAssertFalse(ApprovalPolicy.manual.autoCommit)
    }

    func test_yolo_autoCommit() {
        XCTAssertTrue(ApprovalPolicy.yolo.autoCommit)
    }

    func test_manual_readOnly_bash_tier() {
        XCTAssertEqual(ApprovalPolicy.manual.bashTier, .readOnly)
    }
}
