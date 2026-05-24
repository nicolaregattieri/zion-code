// SlashAutocompleteUITests.swift
// Unit tests for SlashAutocompleteState state machine + SlashCommandRegistry smoke test.
// Phase 14, Task 4.

import XCTest
@testable import Zion

@MainActor
final class SlashAutocompleteUITests: XCTestCase {

    // MARK: Helpers

    private func makeItems(count: Int = 3) -> [SlashItem] {
        (0 ..< count).map { i in
            SlashItem(
                id: "cmd\(i)",
                name: "/cmd\(i)",
                argHint: i == 0 ? "<path>" : nil,
                description: "Command \(i)",
                source: .builtIn,
                bodyLoader: nil
            )
        }
    }

    // MARK: 1. Arrow key navigation

    func test_state_machine_arrow_keys() {
        var state = SlashAutocompleteState()
        let items = makeItems(count: 3)
        state.load(items: items)

        XCTAssertEqual(state.selectedIndex, 0, "Initial selected index is 0")

        state.handleKey(.down)
        XCTAssertEqual(state.selectedIndex, 1, "Down moves selection to 1")

        state.handleKey(.up)
        XCTAssertEqual(state.selectedIndex, 0, "Up moves selection back to 0")

        // Up at top should clamp at 0, not wrap
        state.handleKey(.up)
        XCTAssertEqual(state.selectedIndex, 0, "Up at top stays at 0")
    }

    // MARK: 2. Return key commits selected item

    func test_return_key_commits_selected() {
        var state = SlashAutocompleteState()
        let items = makeItems(count: 3)
        state.load(items: items)

        let committed = state.handleKey(.returnKey)
        XCTAssertNotNil(committed, "Return key should return the committed item")
        XCTAssertEqual(committed?.id, items[0].id, "Committed item is the selected one (index 0)")
        XCTAssertFalse(state.isActive, "State is dismissed after commit")
    }

    // MARK: 3. Escape dismisses panel

    func test_escape_dismisses_panel() {
        var state = SlashAutocompleteState()
        let items = makeItems(count: 3)
        state.load(items: items)

        XCTAssertTrue(state.isActive, "Panel is active before escape")

        state.handleKey(.escape)
        XCTAssertFalse(state.isActive, "Escape should dismiss the state")
        XCTAssertTrue(state.isDismissed, "isDismissed should be true after escape")
    }

    // MARK: 4. Tab commits same as Return

    func test_tab_commits_same_as_return() {
        var state = SlashAutocompleteState()
        let items = makeItems(count: 3)
        state.load(items: items)

        // Navigate to item at index 1
        state.handleKey(.down)
        XCTAssertEqual(state.selectedIndex, 1)

        let committed = state.handleKey(.tab)
        XCTAssertNotNil(committed, "Tab should commit the selected item")
        XCTAssertEqual(committed?.id, items[1].id, "Tab commits the item at selectedIndex 1")
        XCTAssertFalse(state.isActive, "State is dismissed after tab commit")
    }

    // MARK: 5. SlashCommandRegistry.shared smoke test

    func test_slashRegistry_match_returns_matches() async {
        let registry = SlashCommandRegistry.shared
        let results = registry.match(prefix: "/")
        // There are 5 built-in commands minimum (diff, help, clear, compact, context or similar)
        XCTAssertGreaterThanOrEqual(results.count, 4,
            "match(prefix: '/') should return at least 4 items, got \(results.count)")
    }
}
