import SwiftUI

private enum SettingsTab: String, CaseIterable {
    case general, editor, terminal, ai, notifications, mobileAccess

    var label: String {
        switch self {
        case .general:       return L10n("settings.tab.general")
        case .editor:        return L10n("settings.tab.editor")
        case .terminal:      return L10n("settings.tab.terminal")
        case .ai:            return L10n("settings.tab.ai")
        case .notifications: return L10n("settings.tab.notifications")
        case .mobileAccess:  return L10n("settings.tab.mobileAccess")
        }
    }

    var icon: String {
        switch self {
        case .general:       return "gearshape"
        case .editor:        return "pencil.and.outline"
        case .terminal:      return "apple.terminal"
        case .ai:            return "sparkles"
        case .notifications: return "bell.badge"
        case .mobileAccess:  return "iphone.and.arrow.forward"
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            // Custom tab bar
            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 22))
                            Text(tab.label)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .contentShape(Rectangle())
                        .foregroundStyle(selectedTab == tab ? DesignSystem.Colors.actionPrimary : .secondary)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius)
                                .fill(selectedTab == tab ? DesignSystem.Colors.actionPrimary.opacity(0.12) : .clear)
                                .padding(.horizontal, 4)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider()

            // Content area
            Group {
                switch selectedTab {
                case .general:       GeneralSettingsTab()
                case .editor:        EditorSettingsTab()
                case .terminal:      TerminalSettingsTab()
                case .ai:            AISettingsTab()
                case .notifications: NotificationSettingsTab()
                case .mobileAccess:  MobileAccessSettingsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 480, height: 580)
        .tint(DesignSystem.Colors.actionPrimary)
        .onReceive(NotificationCenter.default.publisher(for: .openMobileAccessSettings)) { _ in
            selectedTab = .mobileAccess
        }
    }
}
