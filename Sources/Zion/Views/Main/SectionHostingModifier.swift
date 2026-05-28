import SwiftUI

extension View {
    /// Mount a workspace section view in the ZStack-overlay layout used by
    /// ContentView. Hidden sections stay alive (heavy state like terminals,
    /// graph, chat is preserved across tab switches) but are visually +
    /// interactively + accessibility-inert.
    ///
    /// Also publishes the active section into the environment so descendants
    /// (popovers, dropdowns, keyboard shortcuts) can gate themselves on
    /// "am I actually on screen?" — required because SwiftUI keeps menus /
    /// popovers alive on hidden parents and they leak across tabs.
    func hostedInSection(_ section: AppSection, active: AppSection) -> some View {
        let isActive = section == active
        return self
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
            .disabled(!isActive)
            .environment(\.zionActiveSection, active)
    }
}
