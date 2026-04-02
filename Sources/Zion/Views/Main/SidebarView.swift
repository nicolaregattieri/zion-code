import SwiftUI

struct SidebarView: View {
    @Bindable var model: RepositoryViewModel
    @Binding var selectedSection: AppSection
    @Binding var selectedBranchTreeNodeID: String?
    @Binding var confirmationModeRaw: String
    @Binding var uiLanguageRaw: String
    @Binding var appearanceRaw: String

    @Environment(SparkleUpdater.self) private var updater: SparkleUpdater?
    @AppStorage(UserDefaultsKeys.Sidebar.recentsExpanded) private var isRecentsExpanded: Bool = true
    @State var branchSearchQuery: String = ""
    @State var isNewWorktreeExpanded: Bool = false
    @State var hoveredSection: AppSection?
    @State var hoveredWorktreePath: String?

    let onOpen: () -> Void
    let branchContextMenu: (String) -> AnyView

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                repoSummaryCard

                workspaceCard

                recentProjectsCard

                if model.hasGitWorkspace {
                    worktreesCard
                }

                if model.hasGitWorkspace, model.hasHostingProvider {
                    PRInboxCard(model: model)
                }

                if model.hasGitWorkspace {
                    bridgeAccessCard
                }

                if selectedSection == .graph, model.hasGitWorkspace {
                    sidebarBranchExplorer.padding(.horizontal, 10)
                }

                quickSettingsRow
            }
            .padding(.top, 10).padding(.bottom, 20)
        }
        .frame(minWidth: DesignSystem.Layout.sidebarMinWidth, idealWidth: 360, maxWidth: 420)
        .onAppear {
            model.loadRecentRepositories()
        }
    }

    private var recentProjectsCard: some View {
        Group {
            if !model.recentRepositories.isEmpty {
                GlassCard(spacing: 10) {
                    CardHeader(L10n("Recentes"), icon: "clock.arrow.circlepath") {
                        collapseToggle(isExpanded: $isRecentsExpanded)
                    }

                    if isRecentsExpanded {
                        ScrollViewReader { proxy in
                            ScrollView(showsIndicators: true) {
                                VStack(spacing: 4) {
                                    Color.clear.frame(height: 0).id("recents-top")
                                    ForEach(model.recentRepositories, id: \.self) { url in
                                        RecentProjectRow(
                                            url: url,
                                            isCurrent: model.recentRepositoryRoot(for: model.pendingRepositoryURL ?? model.repositoryURL) == url,
                                            changedCount: model.recentChangedCount(for: url),
                                            worktreeCount: model.recentWorktreeCounts[url] ?? 0
                                        ) {
                                            guard model.recentRepositoryRoot(for: model.repositoryURL) != url else { return }
                                            withAnimation(DesignSystem.Motion.springInteractive) {
                                                model.saveRecentRepository(url)
                                                model.pendingRepositoryURL = url
                                            }
                                            model.nextSectionAfterRepositoryOpen = selectedSection
                                            Task { @MainActor in
                                                try? await Task.sleep(for: .milliseconds(50))
                                                withAnimation(DesignSystem.Motion.springInteractive) {
                                                    proxy.scrollTo("recents-top", anchor: .top)
                                                }
                                                // Let the spring animation (0.3s) complete before
                                                // openRepository runs heavy synchronous work on MainActor
                                                // (terminal stash/restore, file watchers, snapshot capture).
                                                try? await Task.sleep(for: .milliseconds(300))
                                                model.openRepository(url, silent: true)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 220)
                    }
                }
                .padding(.horizontal, 10)
                .featureTourAnchor(.recentRepositories)
            }
        }
    }

    private var repoSummaryCard: some View {
        GlassCard(spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Group {
                    if let logoURL = Bundle.zionResources.url(forResource: "zion-logo", withExtension: "png"),
                       let nsImage = NSImage(contentsOf: logoURL) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.containerCornerRadius, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.repositoryURL?.lastPathComponent ?? L10n("Zion Code")).font(DesignSystem.Typography.sheetTitle).lineLimit(1).help(model.repositoryURL?.lastPathComponent ?? L10n("Zion Code"))
                    Text(model.repositoryURL?.path ?? L10n("Modo editor livre")).font(DesignSystem.Typography.monoLabel).foregroundStyle(.secondary).lineLimit(1).help(model.repositoryURL?.path ?? L10n("Modo editor livre"))
                }
                Spacer(minLength: 0)

                if model.repositoryURL == nil {
                    Button(action: onOpen) {
                        Image(systemName: "folder.badge.plus")
                            .font(DesignSystem.Typography.subtitle)
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Color.accentColor)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(L10n("Abrir Pasta"))
                }
            }
            if model.hasGitWorkspace {
                let isDetached = model.currentBranch.contains("detached")
                let hasStashes = model.stashes.count > 0
                let hasRelease = model.latestReleaseTag != nil
                let chipCount = 2 + (hasStashes ? 1 : 0) + (hasRelease ? 1 : 0)
                FlowLayout(spacing: DesignSystem.Spacing.iconTextGap, maxItemsPerRow: chipCount > 3 ? 2 : chipCount) {
                    StatusChip(
                        title: isDetached ? "HEAD" : L10n("Branch"),
                        value: model.currentBranch,
                        tint: isDetached ? DesignSystem.Colors.warning : DesignSystem.Colors.success,
                        icon: isDetached ? "anchor" : "crown.fill"
                    )
                    StatusChip(title: L10n("Commit"), value: model.headShortHash, tint: DesignSystem.Colors.info, icon: "number")
                    if hasStashes {
                        StatusChip(title: L10n("Stashes"), value: "\(model.stashes.count)", tint: DesignSystem.Colors.brandPrimary, icon: "tray.full.fill")
                    }
                    if let latestTag = model.latestReleaseTag {
                        StatusChip(title: L10n("sidebar.release"), value: latestTag, tint: DesignSystem.Colors.searchHighlight, icon: "tag.fill")
                    }
                }
            }
        }
        .padding(.horizontal, 10)
    }

    private func collapseToggle(isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(DesignSystem.Motion.panel) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            Image(systemName: "chevron.right")
                .font(DesignSystem.Typography.metaBold)
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                .animation(DesignSystem.Motion.panel, value: isExpanded.wrappedValue)
                .iconHitTarget()
        }
        .buttonStyle(.plain)
    }

    private var workspaceCard: some View {
        GlassCard(spacing: 8) {
            CardHeader(L10n("Workspace"), icon: "macwindow.on.rectangle")
            VStack(spacing: 8) {
                ForEach(AppSection.allCases) { section in
                    workspaceButton(for: section)
                }
            }
        }.padding(.horizontal, 10)
        .featureTourAnchor(.workspace)
    }

    private func workspaceButton(for section: AppSection) -> some View {
        let isSelected = selectedSection == section
        let isDisabled = !model.canAccess(section)
        let isHovered = hoveredSection == section

        return Button { selectedSection = section } label: {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.toolbarItemGap) {
                Image(systemName: section.icon)
                    .font(DesignSystem.Typography.sectionTitle)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .opacity(isDisabled ? DesignSystem.Opacity.dim : DesignSystem.Opacity.full)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n(section.title)).font(DesignSystem.Typography.sectionTitle).lineLimit(1)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    Text(L10n(section.subtitle)).font(DesignSystem.Typography.bodySmall).foregroundStyle(.secondary).lineLimit(2)
                        .opacity(isSelected ? DesignSystem.Opacity.full : (isDisabled ? DesignSystem.Opacity.dim : DesignSystem.Opacity.visible))
                }
                .opacity(isDisabled ? DesignSystem.Opacity.dim : DesignSystem.Opacity.full)

                Spacer(minLength: 0)

                if isDisabled {
                    Image(systemName: "lock.fill")
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                        .opacity(DesignSystem.Opacity.muted)
                        .help(L10n("sidebar.locked.hint"))
                } else if section == .graph && model.behindRemoteCount > 0 {
                    Text("\(model.behindRemoteCount)")
                        .font(DesignSystem.Typography.monoMeta)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(DesignSystem.Colors.warning.opacity(0.2))
                        .foregroundStyle(DesignSystem.Colors.warning)
                        .clipShape(Capsule())
                } else if section == .operations && model.stashes.count > 0 {
                    Text("\(model.stashes.count)")
                        .font(DesignSystem.Typography.monoMeta)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(DesignSystem.Colors.info.opacity(0.2))
                        .foregroundStyle(DesignSystem.Colors.info)
                        .clipShape(Capsule())
                }
            }
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.containerCornerRadius)
                    .fill(isSelected ? DesignSystem.Colors.glassHover : (isHovered ? DesignSystem.Colors.glassMinimal : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.containerCornerRadius)
                    .stroke(isSelected ? DesignSystem.Colors.selectionBackground : (isHovered ? DesignSystem.Colors.glassStroke : Color.clear), lineWidth: 1)
            )
            .animation(DesignSystem.Motion.detail, value: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { hovering in
            hoveredSection = hovering ? section : nil
        }
    }

    private var quickSettingsRow: some View {
        GlassCard(spacing: 8) {
            HStack(spacing: 12) {
                // Language flag
                let langRaw = uiLanguageRaw
                let langLabel: String = {
                    switch langRaw {
                    case "pt-BR": return "🇧🇷"
                    case "en": return "🇺🇸"
                    case "es": return "🇪🇸"
                    default: return "🌐"
                    }
                }()
                Text(langLabel).font(DesignSystem.Typography.sheetTitle)

                // AI status
                if model.aiProvider != .none {
                    Image(systemName: "sparkles")
                        .font(DesignSystem.Typography.bodySmall)
                        .foregroundStyle(model.isAIConfigured ? DesignSystem.Colors.ai : .secondary)
                }

                // ntfy status
                if model.isNtfyConfigured {
                    Image(systemName: "bell.fill")
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(DesignSystem.Colors.warning)
                        .help(L10n("Notificações ativas"))
                }

                // Update available
                if let updater, updater.updateAvailable {
                    Button {
                        updater.checkForUpdates()
                    } label: {
                        HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(DesignSystem.Typography.meta)
                            if let version = updater.latestVersion {
                                Text(version)
                                    .font(DesignSystem.Typography.micro)
                            }
                        }
                        .foregroundStyle(DesignSystem.Colors.success)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(DesignSystem.Colors.success.opacity(0.15))
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(L10n("settings.update.available"))
                }

                Spacer()

                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L10n("settings.open.hint"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
    }

    private var bridgeAccessCard: some View {
        GlassCard(spacing: 10) {
            CardHeader(L10n("bridge.entry.title"), icon: "arrow.trianglehead.branch", subtitle: L10n("bridge.entry.subtitle"))

            BridgeAccessButton {
                model.isBridgeVisible = true
            }
        }
        .padding(.horizontal, 10)
    }

}

private struct RecentProjectRow: View {
    let url: URL
    let isCurrent: Bool
    let changedCount: Int?
    let worktreeCount: Int
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: {
            if !isCurrent { onTap() }
        }) {
            HStack(spacing: DesignSystem.Spacing.toolbarItemGap) {
                Image(systemName: "folder.fill")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(isCurrent ? DesignSystem.Colors.success : Color.accentColor.opacity(0.8))
                VStack(alignment: .leading, spacing: 1) {
                    Text(url.lastPathComponent)
                        .font(DesignSystem.Typography.sectionTitle)
                        .lineLimit(1)
                    Text(url.path)
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if worktreeCount > 0 {
                    Text("WT \(worktreeCount)")
                        .font(DesignSystem.Typography.micro)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(DesignSystem.Colors.commitSplit.opacity(0.2))
                        .foregroundStyle(DesignSystem.Colors.commitSplit)
                        .clipShape(Capsule())
                }
                Spacer()

                if let count = changedCount, count > 0 {
                    Text("\(count)")
                        .font(DesignSystem.Typography.monoMeta)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(DesignSystem.Colors.warning.opacity(0.2))
                        .foregroundStyle(DesignSystem.Colors.warning)
                        .clipShape(Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(DesignSystem.Typography.micro)
                    .foregroundStyle(.secondary)
                    .opacity(isCurrent ? 0 : 1)
                    .accessibilityHidden(isCurrent)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.containerCornerRadius)
                    .fill(isCurrent ? DesignSystem.Colors.glassHover : DesignSystem.Colors.glassMinimal)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.containerCornerRadius)
                    .stroke(isCurrent ? DesignSystem.Colors.selectionBackground : (isHovered ? DesignSystem.Colors.glassStroke : Color.clear), lineWidth: 1)
            )
            .animation(DesignSystem.Motion.detail, value: isCurrent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in isHovered = h }
    }
}

private struct BridgeAccessButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n("bridge.title"))
                        .font(DesignSystem.Typography.sectionTitle)
                    Text(L10n("bridge.subtitle"))
                        .font(DesignSystem.Typography.bodySmall)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.right")
                    .font(DesignSystem.Typography.metaBold)
                    .foregroundStyle(DesignSystem.Colors.ai)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.containerCornerRadius)
                    .fill(isHovered ? DesignSystem.Colors.glassHover : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.containerCornerRadius)
                    .stroke(isHovered ? DesignSystem.Colors.glassStroke : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in isHovered = h }
        .help(L10n("bridge.open.hint"))
    }
}
