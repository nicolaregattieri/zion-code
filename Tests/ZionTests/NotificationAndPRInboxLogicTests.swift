import XCTest
@testable import Zion

final class NotificationAndPRInboxLogicTests: XCTestCase {
    private let ntfyEnabledKey = "zion.ntfy.enabled"
    private let ntfyLocalNotificationsKey = "zion.ntfy.localNotifications"
    private let ntfyTopicKey = "zion.ntfy.topic"
    private let ntfyServerURLKey = "zion.ntfy.serverURL"
    private let ntfyEnabledEventsKey = "zion.ntfy.enabledEvents"

    private var savedNtfyEnabledValue: Any?
    private var savedNtfyLocalNotificationsValue: Any?
    private var savedNtfyTopicValue: Any?
    private var savedNtfyServerURLValue: Any?
    private var savedNtfyEnabledEventsValue: Any?

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        savedNtfyEnabledValue = defaults.object(forKey: ntfyEnabledKey)
        savedNtfyLocalNotificationsValue = defaults.object(forKey: ntfyLocalNotificationsKey)
        savedNtfyTopicValue = defaults.object(forKey: ntfyTopicKey)
        savedNtfyServerURLValue = defaults.object(forKey: ntfyServerURLKey)
        savedNtfyEnabledEventsValue = defaults.object(forKey: ntfyEnabledEventsKey)

        defaults.removeObject(forKey: ntfyEnabledKey)
        defaults.removeObject(forKey: ntfyLocalNotificationsKey)
        defaults.removeObject(forKey: ntfyTopicKey)
        defaults.removeObject(forKey: ntfyServerURLKey)
        defaults.removeObject(forKey: ntfyEnabledEventsKey)
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        if let savedNtfyEnabledValue {
            defaults.set(savedNtfyEnabledValue, forKey: ntfyEnabledKey)
        } else {
            defaults.removeObject(forKey: ntfyEnabledKey)
        }
        if let savedNtfyLocalNotificationsValue {
            defaults.set(savedNtfyLocalNotificationsValue, forKey: ntfyLocalNotificationsKey)
        } else {
            defaults.removeObject(forKey: ntfyLocalNotificationsKey)
        }
        if let savedNtfyTopicValue {
            defaults.set(savedNtfyTopicValue, forKey: ntfyTopicKey)
        } else {
            defaults.removeObject(forKey: ntfyTopicKey)
        }
        if let savedNtfyServerURLValue {
            defaults.set(savedNtfyServerURLValue, forKey: ntfyServerURLKey)
        } else {
            defaults.removeObject(forKey: ntfyServerURLKey)
        }
        if let savedNtfyEnabledEventsValue {
            defaults.set(savedNtfyEnabledEventsValue, forKey: ntfyEnabledEventsKey)
        } else {
            defaults.removeObject(forKey: ntfyEnabledEventsKey)
        }

        savedNtfyEnabledValue = nil
        savedNtfyLocalNotificationsValue = nil
        savedNtfyTopicValue = nil
        savedNtfyServerURLValue = nil
        savedNtfyEnabledEventsValue = nil
        super.tearDown()
    }

    func testNotificationLayoutKeepsPRControlsVisibleWithoutNtfySetup() {
        let state = NotificationSettingsLayoutState.resolve(
            ntfyEnabled: false,
            localNotificationsEnabled: false
        )

        XCTAssertFalse(state.showTopicSection)
        XCTAssertTrue(state.showEventsSection)
        XCTAssertTrue(state.showPRSection)
    }

    func testNotificationLayoutAllowsLocalOnlyPreferences() {
        let state = NotificationSettingsLayoutState.resolve(
            ntfyEnabled: false,
            localNotificationsEnabled: true
        )

        XCTAssertTrue(state.showPreferencesSection)
        XCTAssertFalse(state.showTestSection)
    }

    func testDeliveryPlanAllowsLocalNotificationsWithoutRemotePush() {
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: ntfyEnabledKey)
        defaults.set(true, forKey: ntfyLocalNotificationsKey)
        defaults.set([NtfyEvent.prReviewRequested.rawValue], forKey: ntfyEnabledEventsKey)

        let plan = NtfyClient.deliveryPlan(event: .prReviewRequested, defaults: defaults)

        XCTAssertTrue(plan.eventEnabled)
        XCTAssertTrue(plan.deliverLocal)
        XCTAssertFalse(plan.deliverRemote)
        XCTAssertTrue(plan.shouldSendAnything)
    }

    func testDeliveryPlanRequiresTopicForRemotePush() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: ntfyEnabledKey)
        defaults.set(false, forKey: ntfyLocalNotificationsKey)
        defaults.set("", forKey: ntfyTopicKey)
        defaults.set([NtfyEvent.prAutoReviewComplete.rawValue], forKey: ntfyEnabledEventsKey)

        let plan = NtfyClient.deliveryPlan(event: .prAutoReviewComplete, defaults: defaults)

        XCTAssertFalse(plan.deliverLocal)
        XCTAssertFalse(plan.deliverRemote)
        XCTAssertFalse(plan.shouldSendAnything)
    }

    func testPRInboxAccessStateAllowsGitHubAllOpenWithoutToken() {
        let state = PRInboxCard.accessState(
            for: .allOpen,
            providerKind: .github,
            hasToken: false,
            githubStatus: (installed: false, authenticated: false)
        )

        XCTAssertTrue(state.isAvailable)
        XCTAssertNil(state.message)
    }

    func testPRInboxAccessStateStillBlocksGitHubReviewQueueWithoutAuth() {
        let state = PRInboxCard.accessState(
            for: .forReview,
            providerKind: .github,
            hasToken: false,
            githubStatus: (installed: false, authenticated: false)
        )

        XCTAssertFalse(state.isAvailable)
        XCTAssertEqual(state.message, L10n("pr.gh.notInstalled"))
    }

    func testPRInboxAccessStateRequiresAuthForGitLabAllOpen() {
        let state = PRInboxCard.accessState(
            for: .allOpen,
            providerKind: .gitlab,
            hasToken: false
        )

        XCTAssertFalse(state.isAvailable)
        XCTAssertEqual(state.message, String(format: L10n("pr.inbox.authRequired"), GitHostingKind.gitlab.label))
    }
}
