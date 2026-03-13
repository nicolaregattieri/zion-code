import XCTest
@testable import Zion

@MainActor
final class ShortcutRegistryTests: XCTestCase {
    func testDefaultBindingsMatchEditorAndFileBrowserExpectations() {
        let registry = ShortcutRegistry(userDefaults: UserDefaults(suiteName: #function)!)

        XCTAssertEqual(
            registry.binding(for: .toggleComment),
            ShortcutBinding(key: .character("/"), modifiers: [.command])
        )
        XCTAssertEqual(
            registry.binding(for: .deleteSelection),
            ShortcutBinding(key: .delete, modifiers: [.command])
        )
        XCTAssertEqual(
            registry.binding(for: .showKeyboardShortcuts),
            ShortcutBinding(key: .character("k"), modifiers: [.command, .option])
        )
    }

    func testOverridePersistenceRoundTrips() {
        let suiteName = "ShortcutRegistryTests.\(#function)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated UserDefaults suite")
            return
        }
        userDefaults.removePersistentDomain(forName: suiteName)

        let binding = ShortcutBinding(key: .character("l"), modifiers: [.command, .shift])
        var registry: ShortcutRegistry? = ShortcutRegistry(userDefaults: userDefaults)
        registry?.setOverride(binding, for: .toggleComment)
        registry = nil

        let reloadedRegistry = ShortcutRegistry(userDefaults: userDefaults)
        XCTAssertEqual(reloadedRegistry.binding(for: .toggleComment), binding)

        userDefaults.removePersistentDomain(forName: suiteName)
    }

    func testDisplayStringUsesMacNotation() {
        let registry = ShortcutRegistry(userDefaults: UserDefaults(suiteName: #function)!)

        XCTAssertEqual(registry.displayString(for: .toggleComment), "⌘/")
        XCTAssertEqual(registry.displayString(for: .showKeyboardShortcuts), "⌥⌘K")
    }

    func testConflictLookupIsScopedToContext() {
        let registry = ShortcutRegistry(userDefaults: UserDefaults(suiteName: #function)!)
        let binding = ShortcutBinding(key: .character("f"), modifiers: [.command])

        XCTAssertEqual(registry.conflicts(for: .find, binding: binding), [])
        XCTAssertEqual(registry.actions(for: binding, in: .editor).sorted { $0.rawValue < $1.rawValue }, [.find])
        XCTAssertEqual(registry.actions(for: binding, in: .terminal).sorted { $0.rawValue < $1.rawValue }, [.terminalSearch])
    }
}
