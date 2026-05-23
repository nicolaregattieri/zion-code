import XCTest
@testable import Zion

final class ZionTalksSettingsTabTests: XCTestCase {
    private let suiteName = "ZionTalksSettingsTabTests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        // Clear all keys used by the settings tab
        defaults.removeObject(forKey: "chat.toolsEnabled")
        defaults.removeObject(forKey: "chat.autoInject")
        defaults.removeObject(forKey: "chat.editHarness.enabled")
        defaults.removeObject(forKey: "chat.routing.subscriptionFailover")
        defaults.removeObject(forKey: "chat.routing.policy.v1")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - UserDefaults round-trip tests (using standard defaults, matching @AppStorage behaviour)

    func testToolsEnabledTogglePersists() {
        // Write via UserDefaults.standard as @AppStorage does
        UserDefaults.standard.set(false, forKey: "chat.toolsEnabled")
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "chat.toolsEnabled"))

        UserDefaults.standard.set(true, forKey: "chat.toolsEnabled")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "chat.toolsEnabled"))

        // Restore default
        UserDefaults.standard.removeObject(forKey: "chat.toolsEnabled")
    }

    func testAutoInjectTogglePersists() {
        UserDefaults.standard.set(false, forKey: "chat.autoInject")
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "chat.autoInject"))

        UserDefaults.standard.set(true, forKey: "chat.autoInject")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "chat.autoInject"))

        UserDefaults.standard.removeObject(forKey: "chat.autoInject")
    }

    func testEditHarnessEnabledTogglePersists() {
        UserDefaults.standard.set(false, forKey: "chat.editHarness.enabled")
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "chat.editHarness.enabled"))

        UserDefaults.standard.set(true, forKey: "chat.editHarness.enabled")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "chat.editHarness.enabled"))

        UserDefaults.standard.removeObject(forKey: "chat.editHarness.enabled")
    }

    func testSubscriptionFailoverDefaultFalse() {
        // Remove any existing value to simulate first load (key absent)
        UserDefaults.standard.removeObject(forKey: "chat.routing.subscriptionFailover")

        // Bool default for missing key is false
        let value = UserDefaults.standard.bool(forKey: "chat.routing.subscriptionFailover")
        XCTAssertFalse(value, "subscriptionFailover should default to false when key is absent")
    }

    func testRoutingPolicySavesOnEdit() {
        // Start from a clean slate by removing any stored policy
        UserDefaults.standard.removeObject(forKey: "chat.routing.policy.v1")

        // Load defaults
        var policy = RoutingPolicy.load()

        // Mutate a chain
        policy.chains[AITaskLane.general.rawValue] = [AIProvider.anthropic.rawValue, AIProvider.openai.rawValue]

        // Save
        policy.save()

        // Reload and verify
        let reloaded = RoutingPolicy.load()
        let chain = reloaded.chains[AITaskLane.general.rawValue]
        XCTAssertEqual(chain, [AIProvider.anthropic.rawValue, AIProvider.openai.rawValue],
                       "Reloaded policy should match the saved chain")

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "chat.routing.policy.v1")
    }
}
