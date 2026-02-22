import SwiftUI

struct SidebarView: View {
    @Bindable var model: RepositoryViewModel
    @Binding var selectedSection: AppSection
    @Binding var selectedBranchTreeNodeID: String?
    @Binding var confirmationModeRaw: String
    @Binding var uiLanguageRaw: String
    @Binding var appearanceRaw: String

    @AppStorage("zion.preferredTerminal") private var preferredTerminalRaw: String = ExternalTerminal.terminal.rawValue
    @AppStorage("zion.customTerminalPath") private var customTerminalPath: String = ""

    @AppStorage("zion.sidebar.recentsExpanded") private var isRecentsExpanded: Bool = true
    @State private var branchSearchQuery: String = ""
    @State private var isNewWorktreeExpanded: Bool = false

    let onOpen: () -> Void
    let onOpenInTerminal: () -> Void
    let branchContextMenu: (String) -> AnyView
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                repoSummaryCard

                workspaceCard

                recentProjectsCard

                if model.repositoryURL != nil {
                    worktreesCard
                }

                if model.repositoryURL != nil, model.hasGitHubRemote {
                    PRInboxCard(model: model)
                }

                if selectedSection == .graph, model.repositoryURL != nil {
                    sidebarBranchExplorer.padding(.horizontal, 10)
                }

                quickSettingsRow
            }
            .padding(.top, 10).padding(.bottom, 20)
        }
        .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
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
                                        changedCount: model.backgroundRepoChangedFiles[url],
                                        worktreeCount: model.recentWorktreeCounts[url] ?? 0
                                    ) {
                                        withAnimation { model.openRepository(url) }
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
                    Text(model.repositoryURL?.lastPathComponent ?? L10n("Zion Code")).font(.system(size: 16, weight: .bold)).lineLimit(1)
                    Text(model.repositoryURL?.path ?? L10n("Modo editor livre")).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
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
                HStack(spacing: 8) {
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
                .font(.system(size: 9, weight: .bold))
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
                HStack(spacing: 6) {
                    Text("\(nonCurrentWorktrees.count)")
                        .font(.system(size: 10, weight: .bold))
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
                            .font(.system(size: 10, weight: .semibold))
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
                    .font(.system(size: 11))
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
            HStack(spacing: 8) {
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
                HStack(spacing: 10) {
                    if !model.derivedWorktreeBranch.isEmpty {
                        Text("branch: \(model.derivedWorktreeBranch)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if !model.derivedWorktreePath.isEmpty {
                        Text(model.derivedWorktreePath)
                            .font(.system(size: 9, design: .monospaced))
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
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if model.isWorktreeAdvancedExpanded {
                HStack(spacing: 8) {
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
                .stroke(DesignSystem.Colors.glassHover, lineWidth: 1)
        )
    }

    private func worktreeRow(_ wt: WorktreeItem) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(wt.branch.isEmpty ? URL(fileURLWithPath: wt.path).lastPathComponent : wt.branch)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                Text(wt.path)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Circle()
                        .fill(worktreeStatusColor(wt))
                        .frame(width: 6, height: 6)
                    Text("\(wt.uncommittedCount)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if wt.hasConflicts {
                        Text("⚠")
                            .font(.system(size: 9, weight: .bold))
                    }
                }
            }
            Spacer(minLength: 0)
            Button {
                model.openWorktreeInZion(wt)
                selectedSection = .code
            } label: {
                Image(systemName: "pencil.and.outline")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(L10n("Abrir no Zion Code"))

            Button {
                model.openWorktreeTerminal(wt)
            } label: {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(L10n("Terminal"))

            Button {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = L10n("Remover worktree")
                alert.informativeText = L10n("Deseja remover o worktree %@?", wt.path)
                alert.addButton(withTitle: L10n("Remover"))
                alert.addButton(withTitle: L10n("Cancelar"))
                if alert.runModal() == .alertFirstButtonReturn {
                    model.removeWorktreeAndCloseTerminal(wt)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(L10n("Remover worktree"))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous).fill(DesignSystem.Colors.glassSubtle))
        .overlay(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous).stroke(DesignSystem.Colors.glassHover, lineWidth: 1))
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
        
        return Button { selectedSection = section } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                    .padding(.top, 2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .opacity(isDisabled ? 0.3 : 1.0)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n(section.title)).font(.system(size: 13, weight: .bold)).lineLimit(1)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    Text(L10n(section.subtitle)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                        .opacity(isSelected ? 1.0 : (isDisabled ? 0.3 : 0.7))
                }
                .opacity(isDisabled ? 0.3 : 1.0)

                Spacer(minLength: 0)
                
                if isDisabled {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .opacity(0.5)
                        .padding(.top, 4)
                } else if section == .graph && model.behindRemoteCount > 0 {
                    Text("\(model.behindRemoteCount)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(DesignSystem.Colors.warning.opacity(0.2))
                        .foregroundStyle(DesignSystem.Colors.warning)
                        .clipShape(Capsule())
                        .padding(.top, 4)
                } else if section == .operations && model.stashes.count > 0 {
                    Text("\(model.stashes.count)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(DesignSystem.Colors.info.opacity(0.2))
                        .foregroundStyle(DesignSystem.Colors.info)
                        .clipShape(Capsule())
                        .padding(.top, 4)
                }
            }
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: DesignSystem.Spacing.containerCornerRadius).fill(isSelected ? DesignSystem.Colors.glassHover : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: DesignSystem.Spacing.containerCornerRadius).stroke(isSelected ? Color.primary.opacity(0.15) : Color.clear, lineWidth: 1))
            .animation(DesignSystem.Motion.detail, value: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
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
                Text("\(model.branchInfos.count) \(L10n("refs"))").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)

            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                TextField(L10n("Filtrar branches..."), text: $branchSearchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !branchSearchQuery.isEmpty {
                    Button { branchSearchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
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
                        .font(.title2).foregroundStyle(.secondary)
                    Text(branchSearchQuery.isEmpty ? L10n("Sem branches detectadas") : L10n("Nenhuma branch encontrada"))
                        .font(.headline)
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
        return HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                if node.isGroup { Text(node.title).font(.headline) } else {
                    HStack(spacing: 6) {
                        Image(systemName: isMain ? "shield.fill" : "arrow.triangle.branch").font(.caption).foregroundStyle(isMain ? DesignSystem.Colors.warning : (isCurrent ? Color.accentColor : Color.secondary))
                        Text(node.title).font(.system(.caption, design: .monospaced)).fontWeight(isCurrent || isMain ? .bold : .regular).lineLimit(1)
                        if isCurrent { Text(L10n("current")).font(.system(size: 8, weight: .bold)).padding(.horizontal, 4).padding(.vertical, 1).background(DesignSystem.Colors.selectionBackground).foregroundStyle(Color.accentColor).clipShape(Capsule()) }
                    }
                }
                if !node.subtitle.isEmpty { Text(node.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
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
                    Image(systemName: "trash").font(.caption2).foregroundStyle(DesignSystem.Colors.destructiveMuted)
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
            isCurrent ? RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius).stroke(DesignSystem.Colors.hoverAccent, lineWidth: 1) : nil
        )
        .contentShape(Rectangle())
        .onTapGesture { if let branch = node.branchName { selectedBranchTreeNodeID = node.id; model.branchInput = branch } }
        .onTapGesture(count: 2) { if let branch = node.branchName { selectedBranchTreeNodeID = node.id; model.branchInput = branch; model.setBranchFocus(branch) } }
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
                        .font(.system(size: 11))
                        .foregroundStyle(model.isAIConfigured ? DesignSystem.Colors.ai : .secondary)
                }

                // ntfy status
                if model.isNtfyConfigured {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(DesignSystem.Colors.warning)
                        .help(L10n("Notificações ativas"))
                }

                Spacer()

                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L10n("settings.open.hint"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
    }
}

private struct RecentProjectRow: View {
    let url: URL
    let isCurrent: Bool
    let changedCount: Int?
    let worktreeCount: Int
    let onTap: () -> Void
    @State private var isHovered = false

    private var rowBackground: Color {
        if isCurrent { return DesignSystem.Colors.glassHover }
        if isHovered { return DesignSystem.Colors.glassHover }
        return DesignSystem.Colors.glassMinimal
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(isCurrent ? DesignSystem.Colors.success : Color.accentColor.opacity(0.8))
                VStack(alignment: .leading, spacing: 1) {
                    Text(url.lastPathComponent)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(url.path)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if worktreeCount > 0 {
                    Text("WT \(worktreeCount)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(DesignSystem.Colors.commitSplit.opacity(0.2))
                        .foregroundStyle(DesignSystem.Colors.commitSplit)
                        .clipShape(Capsule())
                }
                Spacer()

                if let count = changedCount, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(DesignSystem.Colors.warning.opacity(0.2))
                        .foregroundStyle(DesignSystem.Colors.warning)
                        .clipShape(Capsule())
                }

                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignSystem.Colors.success)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius).fill(rowBackground))
            .overlay(
                isCurrent ? RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius).strokeBorder(DesignSystem.Colors.glassBorderDark, lineWidth: 1) : nil
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
        .onHover { h in isHovered = h }
    }
}
