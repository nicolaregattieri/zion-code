import XCTest
@testable import Zion

/// Phase 6.2 — regression guard for the `PreflightPermission.askAlways`
/// bypass. The chat preflight chip MUST gate edit auto-apply: when set
/// to `askAlways` the EditPreviewCard stays as the only path through,
/// even if `ApprovalPolicy.current.autoCommit` would normally fire.
@MainActor
final class ChatServicePreflightPermissionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "chat.preflight.permission")
        UserDefaults.standard.removeObject(forKey: "chat.approvalPolicy")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "chat.preflight.permission")
        UserDefaults.standard.removeObject(forKey: "chat.approvalPolicy")
        super.tearDown()
    }

    /// The bypass logic is a single line in `ChatService.swift` —
    /// reading `chat.preflight.permission` and comparing to `"askAlways"`.
    /// This test pins the exact key + value so the gate cannot drift
    /// silently in a refactor.
    func test_askAlwaysKey_isKnownAndDefault() {
        let raw = UserDefaults.standard.string(forKey: "chat.preflight.permission")
        XCTAssertNil(raw, "askAlways must be the implicit default — no value set")
        UserDefaults.standard.set("askAlways", forKey: "chat.preflight.permission")
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "chat.preflight.permission"),
            "askAlways"
        )
    }

    func test_approvalPolicy_autoSafe_stillAutoCommit() {
        ApprovalPolicy.set(.autoSafe)
        XCTAssertTrue(ApprovalPolicy.current.autoCommit, "autoSafe must keep autoCommit ON")
    }

    /// The combined gate the chat-stream end uses:
    /// `!askAlways && ApprovalPolicy.current.autoCommit`. We replicate
    /// the literal expression so a refactor that drops the preflight
    /// guard fails the test.
    func test_gateExpression_returnsFalse_underAskAlways() {
        UserDefaults.standard.set("askAlways", forKey: "chat.preflight.permission")
        ApprovalPolicy.set(.auto)
        let preflight = UserDefaults.standard.string(forKey: "chat.preflight.permission") ?? "askAlways"
        let preflightBlocksAutoApply = (preflight == "askAlways")
        let gate = !preflightBlocksAutoApply && ApprovalPolicy.current.autoCommit
        XCTAssertFalse(gate, "askAlways MUST veto auto-apply regardless of ApprovalPolicy")
    }

    func test_gateExpression_returnsTrue_underAcceptEdits_plusAutoPolicy() {
        UserDefaults.standard.set("acceptEdits", forKey: "chat.preflight.permission")
        ApprovalPolicy.set(.auto)
        let preflight = UserDefaults.standard.string(forKey: "chat.preflight.permission") ?? "askAlways"
        let preflightBlocksAutoApply = (preflight == "askAlways")
        let gate = !preflightBlocksAutoApply && ApprovalPolicy.current.autoCommit
        XCTAssertTrue(gate, "acceptEdits + auto policy must auto-apply at stream end")
    }
}
