import XCTest
@testable import Zion

final class ApprovalPolicyMigrationTests: XCTestCase {
    private func makeDefaults(_ id: String = UUID().uuidString) -> UserDefaults {
        let d = UserDefaults(suiteName: id)!
        d.removePersistentDomain(forName: id)
        return d
    }

    func test_legacy_manual_combination_migrates_to_manual() {
        let d = makeDefaults()
        d.set("planFirst", forKey: "chat.plan.mode")
        d.set(false, forKey: "chat.editHarness.autoCommit")
        d.set("readOnly", forKey: "chat.agent.tier")
        XCTAssertEqual(ApprovalPolicy.derivedFromLegacy(defaults: d), .manual)
    }

    func test_legacy_autosafe_combination_migrates_to_autoSafe() {
        let d = makeDefaults()
        d.set("autoApply", forKey: "chat.plan.mode")
        d.set(true, forKey: "chat.editHarness.autoCommit")
        d.set("workspaceWrite", forKey: "chat.agent.tier")
        XCTAssertEqual(ApprovalPolicy.derivedFromLegacy(defaults: d), .autoSafe)
    }

    func test_legacy_yolo_combination_migrates_to_yolo() {
        let d = makeDefaults()
        d.set("autoApply", forKey: "chat.plan.mode")
        d.set(true, forKey: "chat.editHarness.autoCommit")
        d.set("fullAccess", forKey: "chat.agent.tier")
        XCTAssertEqual(ApprovalPolicy.derivedFromLegacy(defaults: d), .yolo)
    }

    func test_mixed_signals_default_to_autoSafe() {
        let d = makeDefaults()
        d.set("planFirst", forKey: "chat.plan.mode")       // safe
        d.set(true, forKey: "chat.editHarness.autoCommit") // aggressive
        d.set("workspaceWrite", forKey: "chat.agent.tier")
        XCTAssertEqual(ApprovalPolicy.derivedFromLegacy(defaults: d), .autoSafe)
    }

    func test_migrateIfNeeded_writes_only_once() {
        let d = makeDefaults()
        d.set("autoApply", forKey: "chat.plan.mode")
        d.set(true, forKey: "chat.editHarness.autoCommit")
        d.set("workspaceWrite", forKey: "chat.agent.tier")

        let migrated1 = ApprovalPolicy.migrateIfNeeded(defaults: d)
        let migrated2 = ApprovalPolicy.migrateIfNeeded(defaults: d)

        XCTAssertTrue(migrated1)
        XCTAssertFalse(migrated2)
        XCTAssertEqual(d.string(forKey: "chat.approvalPolicy"), "autoSafe")
    }

    func test_derived_knobs_per_policy() {
        XCTAssertEqual(ApprovalPolicy.manual.bashTier, .readOnly)
        XCTAssertEqual(ApprovalPolicy.autoSafe.bashTier, .workspaceWrite)
        XCTAssertEqual(ApprovalPolicy.auto.bashTier, .workspaceWrite)
        XCTAssertEqual(ApprovalPolicy.yolo.bashTier, .fullAccess)

        XCTAssertFalse(ApprovalPolicy.manual.autoCommit)
        XCTAssertTrue(ApprovalPolicy.autoSafe.autoCommit)

        XCTAssertTrue(ApprovalPolicy.autoSafe.asksDestructive)
        XCTAssertFalse(ApprovalPolicy.auto.asksDestructive)
    }

    func test_planMode_knobs_per_policy() {
        XCTAssertEqual(ApprovalPolicy.manual.planMode, .planFirst)
        XCTAssertEqual(ApprovalPolicy.autoSafe.planMode, .autoApply)
        XCTAssertEqual(ApprovalPolicy.auto.planMode, .autoApply)
        XCTAssertEqual(ApprovalPolicy.yolo.planMode, .autoApply)
    }

    func test_no_legacy_keys_defaults_to_autoSafe() {
        let d = makeDefaults()
        // No legacy keys written — all defaults apply.
        // planModeRaw = "planFirst", autoCommit = true (default), tierRaw = "workspaceWrite"
        // Mixed signals (planFirst + autoCommit=true) → autoSafe
        XCTAssertEqual(ApprovalPolicy.derivedFromLegacy(defaults: d), .autoSafe)
    }
}
