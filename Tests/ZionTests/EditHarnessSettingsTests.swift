import XCTest

@MainActor
final class EditHarnessSettingsTests: XCTestCase {

    func testEnabledTogglePersists() {
        let key = "chat.editHarness.enabled"
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertTrue(UserDefaults.standard.object(forKey: key) == nil || UserDefaults.standard.bool(forKey: key) == false)
        UserDefaults.standard.set(false, forKey: key)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: key))
        UserDefaults.standard.set(true, forKey: key)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key))
        UserDefaults.standard.removeObject(forKey: key)
    }

    func testAutoCommitTogglePersists() {
        let key = "chat.editHarness.autoCommit"
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertTrue(UserDefaults.standard.object(forKey: key) == nil || UserDefaults.standard.bool(forKey: key) == false)
        UserDefaults.standard.set(false, forKey: key)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: key))
        UserDefaults.standard.set(true, forKey: key)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key))
        UserDefaults.standard.removeObject(forKey: key)
    }

    func testPreferNativeToolTogglePersists() {
        let key = "chat.editHarness.preferNativeTool"
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertTrue(UserDefaults.standard.object(forKey: key) == nil || UserDefaults.standard.bool(forKey: key) == false)
        UserDefaults.standard.set(false, forKey: key)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: key))
        UserDefaults.standard.set(true, forKey: key)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key))
        UserDefaults.standard.removeObject(forKey: key)
    }
}
