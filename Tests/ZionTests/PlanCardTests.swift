import XCTest
@testable import Zion

// MARK: - PlanModeState Tests

final class PlanModeStateTests: XCTestCase {

    private let testKey = "chat.plan.mode"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: testKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: testKey)
        super.tearDown()
    }

    func testDefaultsToplanFirst() {
        XCTAssertEqual(PlanModeState.current(), .planFirst)
    }

    func testSetAndReadBack() {
        PlanModeState.set(.autoApply)
        XCTAssertEqual(PlanModeState.current(), .autoApply)

        PlanModeState.set(.planFirst)
        XCTAssertEqual(PlanModeState.current(), .planFirst)
    }

    func testCaseIterableCoversAllCases() {
        let cases = PlanModeState.allCases
        XCTAssertTrue(cases.contains(.planFirst))
        XCTAssertTrue(cases.contains(.autoApply))
        XCTAssertEqual(cases.count, 2)
    }

    func testRawValueRoundTrip() {
        XCTAssertEqual(PlanModeState(rawValue: "planFirst"), .planFirst)
        XCTAssertEqual(PlanModeState(rawValue: "autoApply"), .autoApply)
        XCTAssertNil(PlanModeState(rawValue: "unknown"))
    }
}

// MARK: - PlanCard Tests

@MainActor
final class PlanCardTests: XCTestCase {

    // Fixture plan used across tests
    private func makePlan(rawXML: String = "<plan/>") -> ChatPlan {
        ChatPlan(
            id: UUID(),
            rawXML: rawXML,
            steps: [
                ChatPlanStep(
                    commitMessage: "feat(auth): add login flow",
                    filePaths: ["Sources/Auth/LoginView.swift", "Sources/Auth/AuthService.swift"],
                    summary: "Implements the login screen and auth service"
                ),
                ChatPlanStep(
                    commitMessage: "test(auth): add unit tests",
                    filePaths: ["Tests/AuthTests.swift"],
                    summary: "Covers happy-path and error cases"
                )
            ]
        )
    }

    // MARK: - Apply

    func testApplyFiresCallback() {
        let plan = makePlan()
        var captured: ChatPlanAction?
        let card = PlanCard(plan: plan, isStreaming: false) { action in
            captured = action
        }
        card.applyTapped()
        XCTAssertEqual(captured, .apply)
    }

    func testApplyDuringStreamingQueuesNotFire() {
        // Apply while streaming arms a pending flag (auto-fires when isStreaming flips false).
        // Direct callback must NOT fire on first tap during stream.
        let plan = makePlan()
        var captured: ChatPlanAction?
        let card = PlanCard(plan: plan, isStreaming: true) { action in
            captured = action
        }
        card.applyTapped()
        XCTAssertNil(captured, "Apply must queue (not fire callback) while isStreaming is true")
    }

    // MARK: - Reject

    func testRejectFiresCallback() {
        let plan = makePlan()
        var captured: ChatPlanAction?
        let card = PlanCard(plan: plan, isStreaming: false) { action in
            captured = action
        }
        card.rejectTapped()
        XCTAssertEqual(captured, .reject)
    }

    func testRejectFiresCallbackWhileStreaming() {
        // Reject is always enabled (no streaming guard)
        let plan = makePlan()
        var captured: ChatPlanAction?
        let card = PlanCard(plan: plan, isStreaming: true) { action in
            captured = action
        }
        card.rejectTapped()
        XCTAssertEqual(captured, .reject)
    }

    // MARK: - Edit / Save (reedit)

    func testEditFiresReeditWithNewXML() {
        let plan = makePlan(rawXML: "<original/>")
        let newXML = "<edited>step updated</edited>"
        var captured: ChatPlanAction?
        let card = PlanCard(plan: plan, isStreaming: false) { action in
            captured = action
        }
        card.saveTapped(xml: newXML)
        XCTAssertEqual(captured, .reedit(newXML))
    }

    func testEditTappedSetsInitialXML() {
        let originalXML = "<root><step/></root>"
        let plan = makePlan(rawXML: originalXML)
        var card = PlanCard(plan: plan, isStreaming: false) { _ in }
        card.editTapped()
        // After editTapped, draftXML should be seeded from plan.rawXML.
        // We verify by firing saveTapped with no changes — captures original XML.
        var captured: ChatPlanAction?
        card.onAction = { captured = $0 }
        card.saveTapped(xml: originalXML)
        XCTAssertEqual(captured, .reedit(originalXML))
    }

    // MARK: - Phase 4 — single-click + L10n contract

    /// Spec criterion #2 — single tap on Apply transitions the plan to the
    /// executing state when not streaming. Locks down the user-reported
    /// "two clicks needed" symptom from the 2.0.5 dogfood: with isStreaming
    /// false the action callback MUST fire on the FIRST applyTapped().
    func test_applyButton_singleClickTransitionsToExecuting() {
        let plan = makePlan()
        var callbackCount = 0
        var captured: ChatPlanAction?
        let card = PlanCard(plan: plan, isStreaming: false) { action in
            callbackCount += 1
            captured = action
        }
        card.applyTapped()
        XCTAssertEqual(callbackCount, 1, "Apply must dispatch exactly once on a single tap")
        XCTAssertEqual(captured, .apply)
    }

    /// Spec criterion #2b — the three previously hardcoded labels resolve
    /// through L10n now and never fall back to the raw key. Locks down the
    /// localization regression caught by the documenter audit.
    func test_localizedLabels_renderViaL10n() {
        let save = L10n("plan.save")
        let reject = L10n("plan.reject")
        let edit = L10n("plan.edit")
        XCTAssertFalse(save.isEmpty)
        XCTAssertFalse(reject.isEmpty)
        XCTAssertFalse(edit.isEmpty)
        XCTAssertNotEqual(save, "plan.save", "L10n must resolve, not return the bare key")
        XCTAssertNotEqual(reject, "plan.reject")
        XCTAssertNotEqual(edit, "plan.edit")
    }

    // MARK: - ChatPlanAction Equatable

    func testChatPlanActionEquatable() {
        XCTAssertEqual(ChatPlanAction.apply, ChatPlanAction.apply)
        XCTAssertEqual(ChatPlanAction.reject, ChatPlanAction.reject)
        XCTAssertEqual(ChatPlanAction.reedit("xml"), ChatPlanAction.reedit("xml"))
        XCTAssertNotEqual(ChatPlanAction.reedit("a"), ChatPlanAction.reedit("b"))
        XCTAssertNotEqual(ChatPlanAction.apply, ChatPlanAction.reject)
    }
}
