import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label(L10n("settings.tab.general"), systemImage: "gearshape")
                }

            AISettingsTab()
                .tabItem {
                    Label(L10n("settings.tab.ai"), systemImage: "sparkles")
                }

            NotificationSettingsTab()
                .tabItem {
                    Label(L10n("settings.tab.notifications"), systemImage: "bell.badge")
                }
        }
        .frame(width: 480, height: 520)
    }
}
