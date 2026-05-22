import XCTest
@testable import Zion

final class CLIAllowEditsDefaultTests: XCTestCase {

    /// Verifies that `chat.cliAllowEdits` defaults to false on a fresh UserDefaults suite.
    /// Uses a unique suiteName so it cannot be polluted by other tests or the host app.
    func test_cliAllowEdits_defaultsFalse() {
        let suiteName = "com.zion.test.cliAllowEditsDefault.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let value = defaults.bool(forKey: "chat.cliAllowEdits")
        XCTAssertFalse(value, "chat.cliAllowEdits should default to false on a fresh suite")
    }
}
