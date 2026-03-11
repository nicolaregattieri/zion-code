import SwiftUI

struct SidebarView: View {
    @Bindable var model: RepositoryViewModel
    @Binding var selectedSection: AppSection
    @Binding var selectedBranchTreeNodeID: String?
    @Binding var confirmationModeRaw: String
    @Binding var uiLanguageRaw: String
    @Binding var appearanceRaw: String

    @AppStorage("zion.sidebar.recentsExpanded") private var isRecentsExpanded: Bool = true
    @State private var branchSearchQuery: String = ""
    @State private var isNewWorktreeExpanded: Bool = false
    @State private var hoveredSection: AppSection?
    @State private var hoveredWorktreePath: String?

    let onOpen: () -> Void
    let branchContextMenu: (String) -> AnyView
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                repoSummaryCard

                workspaceCard

                if model.repositoryURL != nil {
                    bridgeAccessCard
                }

                recentProjectsCard

                if model.repositoryURL != nil {
                    worktreesCard
                }

                if model.repositoryURL != nil, model.hasHostingProvider {
                    PRInboxCard(model: model)
                }

                if selectedSection == .graph, model.repositoryURL != nil {
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
                        ScrollView(showsIndicators: true) {
                            VStack(spacing: 4) {
                                ForEach(model.recentRepositories, id: \.self) { url in
                                    RecentProjectRow(
                                        url: url,
                                        isCurrent: model.recentRepositoryRoot(for: model.repositoryURL) == url,
                                        changedCount: model.recentChangedCount(for: url),
                                        worktreeCount: model.recentWorktreeCounts[url] ?? 0
                                    ) {
                                        withAnimation {
                                            model.nextSectionAfterRepositoryOpen = selectedSection
                                            model.openRepository(url)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 220)
                    }
                }
                .padding(.horizontal, 10)
            }
        }
    }

    private var repoSummaryCard: some View {
        GlassCard(spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Group {
                    if let logoURL = Bundle.module.url(forResource: "zion-logo", withExtension: "png"),
                       let nsImage = NSImage(contentsOf: logoURL) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.containerCornerRadius, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.repositoryURL?.lastPathComponent ?? L10n("Zion Code")).font(DesignSystem.Typography.sheetTitle).lineLimit(1)
                    Text(model.repositoryURL?.path ?? L10n("Modo editor livre")).font(DesignSystem.Typography.monoLabel).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                
                if model.repositoryURL == nil {
                    Button(action: onOpen) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Color.accentColor)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(L10n("Abrir Pasta"))
                }
            }
            if model.repositoryURL != nil {
                HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                    let isDetached = model.currentBranch.contains("detached")
                    StatusChip(
                        title: isDetached ? "HEAD" : L10n("Branch"),
                        value: model.currentBranch,
                        tint: isDetached ? DesignSystem.Colors.warning : DesignSystem.Colors.success,
                        icon: isDetached ? "anchor" : "crown.fill"
                    )
                    StatusChip(title: L10n("Commit"), value: model.headShortHash, tint: DesignSystem.Colors.info, icon: "number")
                    if model.stashes.count > 0 {
                        StatusChip(title: L10n("Stashes"), value: "\(model.stashes.count)", tint: DesignSystem.Colors.brandPrimary, icon: "tray.full.fill")
                    }
                }
            }
        }.padding(.horizontal, 10)
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
        }
        .buttonStyle(.plain)
        .frame(width: 20, height: 20)
        .contentShape(Rectangle())
    }

    private var nonCurrentWorktrees: [WorktreeItem] {
        model.worktrees.filter { !$0.isCurrent }
    }

    private var worktreesCard: some View {
        GlassCard(spacing: 10) {
            CardHeader(L10n("Worktrees"), icon: "square.split.2x2") {
                HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                    Text("\(nonCurrentWorktrees.count)")
                        .font(DesignSystem.Typography.labelBold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(DesignSystem.Colors.brandPrimary.opacity(0.7)))
                    Button {
                        withAnimation(DesignSystem.Motion.panel) {
                            isNewWorktreeExpanded.toggle()
                        }
                    } label: {
                        Label(L10n("worktree.smart.new"), systemImage: "plus")
                            .font(DesignSystem.Typography.label)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if isNewWorktreeExpanded {
                smartWorktreeInlineForm
            }

            if nonCurrentWorktrees.isEmpty {
                Text(L10n("worktree.smart.empty"))
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(nonCurrentWorktrees) { wt in
                    worktreeRow(wt)
                }
            }
        }.padding(.horizontal, 10)
    }

    private var smartWorktreeInlineForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                Picker(L10n("worktree.smart.prefix"), selection: $model.worktreePrefix) {
                    ForEach(WorktreePrefix.allCases) { prefix in
                        Text(L10n(prefix.l10nKey)).tag(prefix)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)

                TextField(L10n("worktree.smart.name.placeholder"), text: $model.worktreeNameInput)
                    .textFieldStyle(.roundedBorder)

                Button(L10n("worktree.smart.createOpen")) {
                    model.smartCreateWorktree()
                    selectedSection = .code
                    withAnimation(DesignSystem.Motion.panel) {
                        isNewWorktreeExpanded = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.actionPrimary)
                .disabled(!model.canSmartCreateWorktree)
            }

            if !model.derivedWorktreeBranch.isEmpty || !model.derivedWorktreePath.isEmpty {
                HStack(spacing: DesignSystem.Spacing.toolbarItemGap) {
                    if !model.derivedWorktreeBranch.isEmpty {
                        Text("branch: \(model.derivedWorktreeBranch)")
                            .font(DesignSystem.Typography.monoMeta)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if !model.derivedWorktreePath.isEmpty {
                        Text(model.derivedWorktreePath)
                            .font(DesignSystem.Typography.monoMeta)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Button {
                withAnimation(DesignSystem.Motion.panel) {
                    model.isWorktreeAdvancedExpanded.toggle()
                }
            } label: {
                Label(
                    L10n("worktree.smart.advanced"),
                    systemImage: model.isWorktreeAdvancedExpanded ? "chevron.down" : "chevron.right"
                )
                .font(DesignSystem.Typography.label)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if model.isWorktreeAdvancedExpanded {
                HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                    TextField(L10n("/caminho/para/worktree"), text: $model.worktreePathInput)
                        .textFieldStyle(.roundedBorder)
                    TextField(L10n("branch (opcional)"), text: $model.worktreeBranchInput)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                .fill(DesignSystem.Colors.glassSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                .stroke(DesignSystem.Colors.glassBorderDark, lineWidth: 1)
        )
    }

    private func worktreeRow(_ wt: WorktreeItem) -> some View {
        let isHovered = hoveredWorktreePath == wt.path

        return HStack(spacing: DesignSystem.Spacing.iconTextGap) {
            Button {
                model.openWorktreeInZion(
                    wt,
                    navigateToCode: false,
                    sectionAfterOpen: selectedSection
                )
            } label: {
                HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                            Text(wt.branch.isEmpty ? URL(fileURLWithPath: wt.path).lastPathComponent : wt.branch)
                                .font(DesignSystem.Typography.monoBody)
                                .lineLimit(1)
                            if wt.isMainWorktree {
                                Text(L10n("worktree.main.badge"))
                                    .font(DesignSystem.Typography.monoMeta)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(DesignSystem.Colors.success.opacity(0.18))
                                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous))
                                    .foregroundStyle(DesignSystem.Colors.success)
                                    .help(L10n("worktree.main.hint"))
                            }
                        }
                        Text(wt.path)
                            .font(DesignSystem.Typography.monoMeta)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                            Circle()
                                .fill(worktreeStatusColor(wt))
                                .frame(width: 6, height: 6)
                            Text("\(wt.uncommittedCount)")
                                .font(DesignSystem.Typography.monoMeta)
                                .foregroundStyle(.secondary)
                            if wt.hasConflicts {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(DesignSystem.Typography.metaBold)
                                    .foregroundStyle(DesignSystem.Colors.destructive)
                                    .help(L10n("Conflitos"))
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .help(L10n("Abrir no Zion Code"))

            Button {
                model.openWorktreeTerminal(wt)
            } label: {
                Image(systemName: "terminal.fill")
                    .font(DesignSystem.Typography.bodySmall)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(L10n("Terminal"))

            if !wt.isMainWorktree {
                Button {
                    model.requestWorktreeRemoval(wt)
                } label: {
                    Image(systemName: "trash")
                        .font(DesignSystem.Typography.bodySmall)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(L10n("Remover worktree"))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                .fill(isHovered ? DesignSystem.Colors.glassHover : DesignSystem.Colors.glassSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                .stroke(isHovered ? DesignSystem.Colors.glassStroke : DesignSystem.Colors.glassHover, lineWidth: 1)
        )
        .onHover { hovering in
            hoveredWorktreePath = hovering ? wt.path : nil
        }
    }

    private func worktreeStatusColor(_ worktree: WorktreeItem) -> Color {
        if worktree.hasConflicts { return DesignSystem.Colors.destructive }
        if worktree.uncommittedCount > 0 { return DesignSystem.Colors.warning }
        return DesignSystem.Colors.success
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
    }

    private func workspaceButton(for section: AppSection) -> some View {
        let isSelected = selectedSection == section
        let isDisabled = section != .code && model.repositoryURL == nil
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

    private var filteredBranchTree: [BranchTreeNode] {
        guard !branchSearchQuery.isEmpty else { return model.branchTree }
        return model.branchTree.compactMap { filterBranchNode($0, query: branchSearchQuery) }
    }

    private func filterBranchNode(_ node: BranchTreeNode, query: String) -> BranchTreeNode? {
        // Leaf node: match on title
        if node.children.isEmpty {
            return node.title.localizedCaseInsensitiveContains(query) ? node : nil
        }
        // Group node: keep if any child matches
        let filteredChildren = node.children.compactMap { filterBranchNode($0, query: query) }
        if filteredChildren.isEmpty { return nil }
        return BranchTreeNode(
            id: node.id,
            title: node.title,
            subtitle: node.subtitle,
            branchName: node.branchName,
            children: filteredChildren
        )
    }

    private var sidebarBranchExplorer: some View {
        GlassCard(spacing: 0) {
            CardHeader(L10n("Branches"), icon: "arrow.triangle.branch") {
                Text("\(model.branchInfos.count) \(L10n("refs"))").font(DesignSystem.Typography.label).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)

            HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                Image(systemName: "magnifyingglass")
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(.secondary)
                TextField(L10n("Filtrar branches..."), text: $branchSearchQuery)
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Typography.bodySmall)
                if !branchSearchQuery.isEmpty {
                    Button { branchSearchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(DesignSystem.Typography.label)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(DesignSystem.Colors.glassSubtle)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()
            if filteredBranchTree.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: branchSearchQuery.isEmpty ? "arrow.triangle.branch" : "magnifyingglass")
                        .font(DesignSystem.Typography.iconLarge).foregroundStyle(.secondary)
                    Text(branchSearchQuery.isEmpty ? L10n("Sem branches detectadas") : L10n("Nenhuma branch encontrada"))
                        .font(DesignSystem.Typography.sheetTitle)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                List(selection: $selectedBranchTreeNodeID) {
                    ForEach(filteredBranchTree) { root in
                        OutlineGroup([root], children: \.outlineChildren) { node in
                            branchTreeNodeRow(node).tag(node.id)
                        }
                    }
                }
                .listStyle(.sidebar)
                .controlSize(.small)
                .frame(minHeight: 120, maxHeight: 250)
            }
        }
    }

    private func branchTreeNodeRow(_ node: BranchTreeNode) -> some View {
        let isMain = ["main", "master", "develop", "dev"].contains(node.title.lowercased())
        let isCurrent = node.branchName == model.currentBranch
        let isFocusLoading = node.branchName == model.branchFocusLoadingBranch && model.isBranchFocusLoading
        return HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
            VStack(alignment: .leading, spacing: 2) {
                if node.isGroup { Text(node.title).font(DesignSystem.Typography.sheetTitle) } else {
                    HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                        if isFocusLoading {
                            ProgressView()
                                .controlSize(.mini)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: isMain ? "shield.fill" : "arrow.triangle.branch")
                                .font(DesignSystem.Typography.label)
                                .foregroundStyle(isMain ? DesignSystem.Colors.warning : (isCurrent ? Color.accentColor : Color.secondary))
                        }
                        Text(node.title).font(DesignSystem.Typography.monoLabel).fontWeight(isCurrent || isMain ? .bold : .regular).lineLimit(1)
                        if isCurrent { Text(L10n("current")).font(DesignSystem.Typography.micro).padding(.horizontal, 4).padding(.vertical, 1).background(DesignSystem.Colors.selectionBackground).foregroundStyle(Color.accentColor).clipShape(Capsule()) }
                    }
                }
                if !node.subtitle.isEmpty { Text(node.subtitle).font(DesignSystem.Typography.meta).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
            if let branch = node.branchName, !isMain, !isCurrent {
                Button {
                    let alert = NSAlert()
                    alert.messageText = L10n("Remover branch local")
                    alert.informativeText = L10n("Deseja remover a branch local %@?", branch)
                    alert.addButton(withTitle: L10n("Remover"))
                    alert.addButton(withTitle: L10n("Cancelar"))
                    if alert.runModal() == .alertFirstButtonReturn {
                        model.deleteLocalBranch(branch, force: false)
                    }
                } label: {
                    Image(systemName: "trash").font(DesignSystem.Typography.meta).foregroundStyle(DesignSystem.Colors.destructiveMuted)
                }
                .buttonStyle(.plain)
                .padding(4)
                .background(DesignSystem.Colors.destructiveBg)
                .clipShape(Circle())
            }
        }
        .padding(.vertical, node.isGroup ? 4 : 2)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius)
                .fill(isCurrent ? DesignSystem.Colors.selectionBackground : Color.clear)
        )
        .overlay(
            isCurrent ? RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius).stroke(DesignSystem.Colors.selectionBorder, lineWidth: 1) : nil
        )
        .contentShape(Rectangle())
        .onTapGesture { if let branch = node.branchName { selectedBranchTreeNodeID = node.id; model.branchInput = branch } }
        .onTapGesture(count: 2) {
            if let branch = node.branchName, !isFocusLoading {
                selectedBranchTreeNodeID = node.id
                model.branchInput = branch
                model.setBranchFocus(branch)
            }
        }
        .contextMenu {
            if let branch = node.branchName {
                branchContextMenu(branch)
            }
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
                Text(langLabel).font(.system(size: 16))

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

            Button {
                model.isBridgeVisible = true
            } label: {
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n("bridge.open.hint"))
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
