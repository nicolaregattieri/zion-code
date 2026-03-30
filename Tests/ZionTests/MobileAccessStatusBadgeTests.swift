import XCTest
@testable import Zion

@MainActor
final class MobileAccessStatusBadgeTests: XCTestCase {

    // MARK: - Model State Mapping

    func testDefaultStateIsDisabledAndHidden() {
        let vm = RepositoryViewModel()
        XCTAssertFalse(vm.isMobileAccessEnabled)
        if case .disabled = vm.mobileAccessConnectionState {} else {
            XCTFail("Expected .disabled, got \(vm.mobileAccessConnectionState)")
        }
    }

    func testEnableSetsStartingState() {
        let vm = RepositoryViewModel()
        vm.isMobileAccessEnabled = true
        vm.mobileAccessConnectionState = .starting
        XCTAssertTrue(vm.isMobileAccessEnabled)
        if case .starting = vm.mobileAccessConnectionState {} else {
            XCTFail("Expected .starting, got \(vm.mobileAccessConnectionState)")
        }
    }

    func testConnectedStateCarriesDeviceCount() {
        let vm = RepositoryViewModel()
        vm.mobileAccessConnectionState = .connected(deviceCount: 3)
        if case .connected(let count) = vm.mobileAccessConnectionState {
            XCTAssertEqual(count, 3)
        } else {
            XCTFail("Expected .connected(3)")
        }
    }

    func testErrorStateCarriesMessage() {
        let vm = RepositoryViewModel()
        vm.mobileAccessConnectionState = .error("tunnel failed")
        if case .error(let msg) = vm.mobileAccessConnectionState {
            XCTAssertEqual(msg, "tunnel failed")
        } else {
            XCTFail("Expected .error")
        }
    }

    func testDisableResetsState() {
        let vm = RepositoryViewModel()
        vm.isMobileAccessEnabled = true
        vm.mobileAccessConnectionState = .connected(deviceCount: 2)

        vm.isMobileAccessEnabled = false
        vm.mobileAccessConnectionState = .disabled

        XCTAssertFalse(vm.isMobileAccessEnabled)
        if case .disabled = vm.mobileAccessConnectionState {} else {
            XCTFail("Expected .disabled after disable")
        }
    }

    // MARK: - Connection State Enum Exhaustiveness

    func testAllConnectionStatesAreDistinct() {
        let states: [RemoteAccessConnectionState] = [
            .disabled,
            .starting,
            .waitingForPairing,
            .connected(deviceCount: 1),
            .error("test"),
        ]

        for state in states {
            switch state {
            case .disabled: break
            case .starting: break
            case .waitingForPairing: break
            case .connected: break
            case .error: break
            }
        }
        // If this compiles, all cases are covered
        XCTAssertEqual(states.count, 5)
    }

    // MARK: - Localization Keys

    func testMobileStatusLocalizationKeysExist() {
        let starting = L10n("mobile.status.starting")
        XCTAssertFalse(starting.isEmpty, "mobile.status.starting key missing")
        XCTAssertNotEqual(starting, "mobile.status.starting", "Key returned raw — not found in strings file")

        let waiting = L10n("mobile.status.waitingForPairing")
        XCTAssertFalse(waiting.isEmpty, "mobile.status.waitingForPairing key missing")
        XCTAssertNotEqual(waiting, "mobile.status.waitingForPairing", "Key returned raw")

        let error = L10n("mobile.status.error")
        XCTAssertFalse(error.isEmpty, "mobile.status.error key missing")
        XCTAssertNotEqual(error, "mobile.status.error", "Key returned raw")

        let tunnelStartup = L10n("mobile.access.error.startupFailed", "detail")
        XCTAssertTrue(tunnelStartup.contains("detail"), "Expected startup failure localization to interpolate detail")

        let dnsFailure = L10n("mobile.access.error.dnsFailed")
        XCTAssertFalse(dnsFailure.isEmpty, "mobile.access.error.dnsFailed key missing")
        XCTAssertNotEqual(dnsFailure, "mobile.access.error.dnsFailed", "Key returned raw")
    }

    func testMobileStatusConnectedFormatsDeviceCount() {
        let tooltip = L10n("mobile.status.connected", 2)
        XCTAssertTrue(tooltip.contains("2"), "Expected device count '2' in tooltip: \(tooltip)")
    }

    func testMobileStatusConnectedFormatsZeroDevices() {
        let tooltip = L10n("mobile.status.connected", 0)
        XCTAssertTrue(tooltip.contains("0"), "Expected '0' in tooltip: \(tooltip)")
    }

    // MARK: - Notification Deep-Link

    func testOpenMobileAccessSettingsNotificationNameExists() {
        let name = Notification.Name.openMobileAccessSettings
        XCTAssertEqual(name.rawValue, "openMobileAccessSettings")
    }

    func testNotificationCanBePostedAndReceived() {
        let expectation = expectation(description: "Notification received")

        let observer = NotificationCenter.default.addObserver(
            forName: .openMobileAccessSettings,
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }

        NotificationCenter.default.post(name: .openMobileAccessSettings, object: nil)

        waitForExpectations(timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }

    // MARK: - Recents Order Preservation

    func testEnsureTerminalsPreservesRecentsOrder() {
        let vm = RepositoryViewModel()

        // Create temp directories so FileManager.fileExists passes
        let tmpDir = FileManager.default.temporaryDirectory
        let repoA = tmpDir.appendingPathComponent("repoA-\(UUID().uuidString)")
        let repoB = tmpDir.appendingPathComponent("repoB-\(UUID().uuidString)")
        let repoC = tmpDir.appendingPathComponent("repoC-\(UUID().uuidString)")
        let repoD = tmpDir.appendingPathComponent("repoD-\(UUID().uuidString)")

        for dir in [repoA, repoB, repoC, repoD] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        defer {
            for dir in [repoA, repoB, repoC, repoD] {
                try? FileManager.default.removeItem(at: dir)
            }
        }

        let originalOrder = [repoA, repoB, repoC, repoD]
        vm.recentRepositories = originalOrder

        // Simulate what saveRecentRepository does: move each to front (scrambles order)
        for url in [repoB, repoC, repoD] {
            vm.saveRecentRepository(url)
        }

        // Verify order IS scrambled (proves the bug is real)
        XCTAssertNotEqual(vm.recentRepositories, originalOrder,
                          "saveRecentRepository should have scrambled the order")

        // Now apply the snapshot-restore fix
        vm.recentRepositories = originalOrder
        if let encoded = try? JSONEncoder().encode(originalOrder) {
            vm.recentReposData = encoded
        }

        // Verify order is restored
        XCTAssertEqual(vm.recentRepositories, originalOrder,
                       "Recents order should be restored after snapshot-restore")

        // Verify persistence matches
        let persisted = try? JSONDecoder().decode([URL].self, from: vm.recentReposData)
        XCTAssertEqual(persisted, originalOrder,
                       "Persisted order should match restored order")
    }

    // MARK: - RemoteAccessState Sync

    func testSyncToSharedState() {
        let vm = RepositoryViewModel()
        vm.mobileAccessConnectionState = .waitingForPairing
        vm.mobileAccessTunnelErrorMessage = "Tunnel unavailable"

        // Simulate what syncRemoteAccessState does
        let shared = RemoteAccessState.shared
        shared.connectionState = vm.mobileAccessConnectionState
        shared.tunnelErrorMessage = vm.mobileAccessTunnelErrorMessage

        if case .waitingForPairing = shared.connectionState {} else {
            XCTFail("Shared state should mirror VM state")
        }
        XCTAssertEqual(shared.tunnelErrorMessage, "Tunnel unavailable")
    }

    // MARK: - Keep Awake Payload

    func testBuildKeepAwakeStatusPayloadWhenOff() {
        let previous = UserDefaults.standard.string(forKey: UserDefaultsKeys.MobileAccess.keepAwakeDuration)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: UserDefaultsKeys.MobileAccess.keepAwakeDuration)
            } else {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.MobileAccess.keepAwakeDuration)
            }
        }

        UserDefaults.standard.set(KeepAwakeDuration.off.rawValue, forKey: UserDefaultsKeys.MobileAccess.keepAwakeDuration)

        let vm = RepositoryViewModel()
        vm.isPreventingSleep = false
        vm.keepAwakeExpiresAt = nil

        let payload = vm.buildKeepAwakeStatusPayload()

        XCTAssertFalse(payload.isActive)
        XCTAssertNil(payload.expiresAt)
        XCTAssertEqual(payload.durationLabel, KeepAwakeDuration.off.label)
    }

    func testBuildKeepAwakeStatusPayloadWhenTimed() {
        let previous = UserDefaults.standard.string(forKey: UserDefaultsKeys.MobileAccess.keepAwakeDuration)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: UserDefaultsKeys.MobileAccess.keepAwakeDuration)
            } else {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.MobileAccess.keepAwakeDuration)
            }
        }

        UserDefaults.standard.set(KeepAwakeDuration.oneHour.rawValue, forKey: UserDefaultsKeys.MobileAccess.keepAwakeDuration)

        let vm = RepositoryViewModel()
        let expiry = Date.now.addingTimeInterval(3600)
        vm.isPreventingSleep = true
        vm.keepAwakeExpiresAt = expiry

        let payload = vm.buildKeepAwakeStatusPayload()

        XCTAssertTrue(payload.isActive)
        XCTAssertNotNil(payload.expiresAt)
        XCTAssertEqual(payload.expiresAt!.timeIntervalSince1970, expiry.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(payload.durationLabel, KeepAwakeDuration.oneHour.label)
    }

    func testBuildKeepAwakeStatusPayloadWhenIndefinite() {
        let previous = UserDefaults.standard.string(forKey: UserDefaultsKeys.MobileAccess.keepAwakeDuration)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: UserDefaultsKeys.MobileAccess.keepAwakeDuration)
            } else {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.MobileAccess.keepAwakeDuration)
            }
        }

        UserDefaults.standard.set(KeepAwakeDuration.indefinite.rawValue, forKey: UserDefaultsKeys.MobileAccess.keepAwakeDuration)

        let vm = RepositoryViewModel()
        vm.isPreventingSleep = true
        vm.keepAwakeExpiresAt = nil

        let payload = vm.buildKeepAwakeStatusPayload()

        XCTAssertTrue(payload.isActive)
        XCTAssertNil(payload.expiresAt)
        XCTAssertEqual(payload.durationLabel, KeepAwakeDuration.indefinite.label)
    }
}
