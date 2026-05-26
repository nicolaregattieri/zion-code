import SwiftUI

/// Propagates the currently-visible top-level section (Code / Graph /
/// Operations / Chat / etc.) into the view tree so widgets with
/// keyboard-shortcut bindings can gate themselves on whether their host
/// screen is the one the user is actually looking at.
///
/// Without this, ZStack-overlay layouts (ContentView keeps every screen
/// alive and only toggles opacity) cause shortcuts from non-visible
/// screens to fire — e.g. ⌥⌘X from Zion Talks was triggering the terminal
/// mic because both screens were mounted simultaneously.
private struct ZionActiveSectionKey: EnvironmentKey {
    static let defaultValue: AppSection? = nil
}

extension EnvironmentValues {
    var zionActiveSection: AppSection? {
        get { self[ZionActiveSectionKey.self] }
        set { self[ZionActiveSectionKey.self] = newValue }
    }
}
