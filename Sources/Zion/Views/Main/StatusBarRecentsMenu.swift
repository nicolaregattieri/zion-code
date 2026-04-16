import SwiftUI

struct StatusBarRecentsMenu: View {
    @Bindable var model: RepositoryViewModel
    @Binding var splitViewVisibility: NavigationSplitViewVisibility
    var isCompactLabel: Bool = false
    var zionModeEnabled: Bool = false
    var onOpenFolder: () -> Void

    private let maxRecents = 8

    var body: some View {
        Menu {
            recentsSection
            Divider()
            Button {
                onOpenFolder()
            } label: {
                Label(L10n("statusBar.recents.openFolder"), systemImage: "folder.badge.plus")
            }
            Button {
                splitViewVisibility = .all
            } label: {
                Label(L10n("statusBar.recents.showProjects"), systemImage: "sidebar.left")
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(DesignSystem.Typography.metaSemibold)
                if !isCompactLabel {
                    Text(L10n("statusBar.recents.title"))
                        .font(DesignSystem.Typography.labelSemibold)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n("statusBar.recents.title"))
        .accessibilityLabel(L10n("statusBar.recents.title"))
    }

    @ViewBuilder
    private var recentsSection: some View {
        let visible = Array(model.recentRepositories.prefix(maxRecents))
        if visible.isEmpty {
            Text(L10n("statusBar.recents.empty"))
                .font(DesignSystem.Typography.bodySmall)
                .foregroundStyle(.secondary)
        } else {
            ForEach(visible, id: \.self) { url in
                Button {
                    model.saveRecentRepository(url)
                    model.openRepository(url)
                } label: {
                    Label(url.lastPathComponent, systemImage: "folder")
                }
            }
        }
    }
}
