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

    func testDefaultsHaveNoSameContextConflicts() {
        let registry = ShortcutRegistry(userDefaults: UserDefaults(suiteName: #function)!)
        var seen: [ShortcutContext: [ShortcutBinding: ShortcutActionID]] = [:]

        for definition in registry.definitions {
            guard let binding = definition.defaultBinding else { continue }
            if let existing = seen[definition.context]?[binding] {
                XCTFail("Conflict: \(definition.id) and \(existing) share \(binding.displayString) in \(definition.context)")
            }
            seen[definition.context, default: [:]][binding] = definition.id
        }
    }

    func testReservedBindingsAreRejected() {
        let registry = ShortcutRegistry(userDefaults: UserDefaults(suiteName: #function)!)

        let cmdQ = ShortcutBinding(key: .character("q"), modifiers: [.command])
        let cmdC = ShortcutBinding(key: .character("c"), modifiers: [.command])
        let cmdShiftR = ShortcutBinding(key: .character("r"), modifiers: [.command, .shift])

        XCTAssertTrue(registry.isReserved(cmdQ))
        XCTAssertTrue(registry.isReserved(cmdC))
        XCTAssertFalse(registry.isReserved(cmdShiftR))
    }

    func testResetAllClearsOverrides() {
        let suiteName = "ShortcutRegistryTests.\(#function)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated UserDefaults suite")
            return
        }
        userDefaults.removePersistentDomain(forName: suiteName)

        let registry = ShortcutRegistry(userDefaults: userDefaults)
        registry.setOverride(.init(key: .character("l"), modifiers: [.command]), for: .save)
        registry.setOverride(.init(key: .character("k"), modifiers: [.command]), for: .find)

        XCTAssertEqual(registry.overrides.count, 2)

        registry.resetAllOverrides()
        XCTAssertTrue(registry.overrides.isEmpty)

        userDefaults.removePersistentDomain(forName: suiteName)
    }

    func testUpdatedDefaultBindings() {
        let registry = ShortcutRegistry(userDefaults: UserDefaults(suiteName: #function)!)

        XCTAssertEqual(
            registry.binding(for: .findReplace),
            ShortcutBinding(key: .character("f"), modifiers: [.command, .option]),
            "findReplace should be Cmd+Opt+F (was Cmd+H)"
        )
        XCTAssertEqual(
            registry.binding(for: .goToLine),
            ShortcutBinding(key: .character("g"), modifiers: [.control]),
            "goToLine should be Ctrl+G (was Cmd+G)"
        )
        XCTAssertEqual(
            registry.binding(for: .zenMode),
            ShortcutBinding(key: .character("t"), modifiers: [.command]),
            "zenMode should be Cmd+T"
        )
        XCTAssertEqual(
            registry.binding(for: .newTerminalTab),
            ShortcutBinding(key: .character("t"), modifiers: [.command, .shift]),
            "newTerminalTab should be Cmd+Shift+T"
        )
        XCTAssertEqual(
            registry.binding(for: .navigateCodeByLetter),
            ShortcutBinding(key: .character("e"), modifiers: [.command]),
            "navigateCodeByLetter should be Cmd+E"
        )
        XCTAssertEqual(
            registry.binding(for: .navigateGraphByLetter),
            ShortcutBinding(key: .character("g"), modifiers: [.command]),
            "navigateGraphByLetter should be Cmd+G"
        )
        XCTAssertEqual(
            registry.binding(for: .bisectGood),
            ShortcutBinding(key: .character("g"), modifiers: [.command, .control]),
            "bisectGood should be Cmd+Ctrl+G"
        )
    }

    func testNewActionShortcuts() {
        let registry = ShortcutRegistry(userDefaults: UserDefaults(suiteName: #function)!)

        XCTAssertEqual(
            registry.binding(for: .quickCommit),
            ShortcutBinding(key: .return, modifiers: [.command])
        )
        XCTAssertEqual(
            registry.binding(for: .stageAll),
            ShortcutBinding(key: .character("a"), modifiers: [.command, .shift])
        )
    }
}
