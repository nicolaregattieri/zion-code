import SwiftUI

struct SidebarView: View {
    @Bindable var model: RepositoryViewModel
    @Binding var selectedSection: AppSection?
    @Binding var selectedBranchTreeNodeID: String?
    @Binding var confirmationModeRaw: String
    @Binding var uiLanguageRaw: String
    @Binding var appearanceRaw: String
    
    @AppStorage("zion.preferredTerminal") private var preferredTerminalRaw: String = ExternalTerminal.terminal.rawValue
    @AppStorage("zion.customTerminalPath") private var customTerminalPath: String = ""

    @State private var aiKeyInput: String = ""
    @State private var isEditingAIKey: Bool = false
    @AppStorage("zion.sidebar.recentsExpanded") private var isRecentsExpanded: Bool = true
    @AppStorage("zion.sidebar.settingsExpanded") private var isSettingsExpanded: Bool = false

    let onOpen: () -> Void
    let onOpenInTerminal: () -> Void
    let branchContextMenu: (String) -> AnyView
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                repoSummaryCard

                workspaceCard

                recentProjectsCard

                if model.repositoryURL != nil, nonCurrentWorktrees.count > 0 {
                    worktreesCard
                }

                if selectedSection == .graph, model.repositoryURL != nil {
                    sidebarBranchExplorer.padding(.horizontal, 10)
                }

                settingsCard
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
                        VStack(spacing: 4) {
                            ForEach(model.recentRepositories, id: \.self) { url in
                                RecentProjectRow(url: url, isCurrent: url == model.repositoryURL, changedCount: model.backgroundRepoChangedFiles[url]) {
                                    withAnimation { model.openRepository(url) }
                                }
                            }
                        }
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
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                        tint: isDetached ? .orange : .green,
                        icon: isDetached ? "anchor" : "crown.fill"
                    )
                    StatusChip(title: L10n("Commit"), value: model.headShortHash, tint: .blue, icon: "number")
                }
            }
        }.padding(.horizontal, 10)
    }

    private func collapseToggle(isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                .animation(.easeInOut(duration: 0.2), value: isExpanded.wrappedValue)
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
                Text("\(nonCurrentWorktrees.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.purple.opacity(0.7)))
            }
            ForEach(nonCurrentWorktrees) { wt in
                worktreeRow(wt)
            }
        }.padding(.horizontal, 10)
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
            }
            Spacer(minLength: 0)
            Button {
                model.openWorktreeTerminal(wt)
                selectedSection = .code
            } label: {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(L10n("Terminal"))

            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: wt.path)
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(L10n("Abrir"))

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
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DesignSystem.Colors.glassSubtle))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(DesignSystem.Colors.glassHover, lineWidth: 1))
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
        let isSelected = (selectedSection ?? .graph) == section
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
                        .background(Color.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                        .padding(.top, 4)
                }
            }
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(isSelected ? Color.primary.opacity(0.08) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Color.primary.opacity(0.15) : Color.clear, lineWidth: 1))
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private var sidebarBranchExplorer: some View {
        GlassCard(spacing: 0) {
            CardHeader(L10n("Branches"), icon: "arrow.triangle.branch") {
                Text("\(model.branchInfos.count) \(L10n("refs"))").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
            Divider()
            if model.branchTree.isEmpty {
                VStack(spacing: 8) { Image(systemName: "arrow.triangle.branch").font(.title2).foregroundStyle(.secondary); Text(L10n("Sem branches detectadas")).font(.headline) }.frame(maxWidth: .infinity, minHeight: 120)
            } else {
                List(selection: $selectedBranchTreeNodeID) {
                    ForEach(model.branchTree) { root in
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
                        Image(systemName: isMain ? "shield.fill" : "arrow.triangle.branch").font(.caption).foregroundStyle(isMain ? Color.orange : (isCurrent ? Color.accentColor : Color.secondary))
                        Text(node.title).font(.system(.caption, design: .monospaced)).fontWeight(isCurrent || isMain ? .bold : .regular).lineLimit(1)
                        if isCurrent { Text(L10n("current")).font(.system(size: 8, weight: .bold)).padding(.horizontal, 4).padding(.vertical, 1).background(Color.accentColor.opacity(0.2)).foregroundStyle(Color.accentColor).clipShape(Capsule()) }
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
                    Image(systemName: "trash").font(.caption2).foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .padding(4)
                .background(Color.red.opacity(0.1))
                .clipShape(Circle())
            }
        }
        .padding(.vertical, node.isGroup ? 4 : 2)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isCurrent ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .overlay(
            isCurrent ? RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor.opacity(0.3), lineWidth: 1) : nil
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

    private var settingsCard: some View {
        GlassCard(spacing: 12) {
            CardHeader(L10n("Configuracoes"), icon: "gearshape") {
                collapseToggle(isExpanded: $isSettingsExpanded)
            }

            if isSettingsExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    // Language
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n("Idioma")).font(.caption).foregroundStyle(.secondary)
                        Picker("", selection: $uiLanguageRaw) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.label).tag(language.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    Divider().opacity(0.1)

                    // Appearance
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n("Aparencia")).font(.caption).foregroundStyle(.secondary)
                        Picker("", selection: $appearanceRaw) {
                            ForEach(AppAppearance.allCases) { mode in
                                Text(mode.label).tag(mode.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    Divider().opacity(0.1)

                    // External Terminal
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "terminal")
                                .font(.system(size: 9))
                                .foregroundStyle(.blue)
                            Text(L10n("Terminal Externo")).font(.caption).foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Picker("", selection: $preferredTerminalRaw) {
                                ForEach(ExternalTerminal.allCases) { term in
                                    Text(term.label).tag(term.rawValue)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .onChange(of: preferredTerminalRaw) { _, val in
                                if val == "custom" { pickCustomApp() }
                            }
                            if preferredTerminalRaw == "custom" && !customTerminalPath.isEmpty {
                                Text(URL(fileURLWithPath: customTerminalPath).lastPathComponent)
                                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                            }
                        }
                    }

                    Divider().opacity(0.1)

                    // AI Provider
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9))
                                .foregroundStyle(.purple)
                            Text(L10n("Assistente IA")).font(.caption).foregroundStyle(.secondary)
                        }
                        Picker("", selection: $model.aiProvider) {
                            ForEach(AIProvider.allCases) { provider in
                                Text(provider.label).tag(provider)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .onChange(of: model.aiProvider) { _, _ in
                            isEditingAIKey = false
                            aiKeyInput = ""
                        }

                        if model.aiProvider != .none {
                            let hasKey = !model.aiAPIKey.isEmpty
                            
                            if hasKey && !isEditingAIKey {
                                HStack {
                                    Label(L10n("Chave registrada"), systemImage: "lock.fill")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.green.opacity(0.8))
                                    
                                    Spacer()
                                    
                                    Button(L10n("Alterar")) {
                                        aiKeyInput = model.aiAPIKey
                                        isEditingAIKey = true
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.accentColor)
                                }
                                .padding(.vertical, 2)
                            } else {
                                VStack(alignment: .trailing, spacing: 6) {
                                    SecureField(L10n("Chave de API"), text: $aiKeyInput)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 11, design: .monospaced))
                                        .onSubmit {
                                            if !aiKeyInput.isEmpty {
                                                model.aiAPIKey = aiKeyInput
                                                isEditingAIKey = false
                                            }
                                        }
                                    
                                    HStack {
                                        if isEditingAIKey {
                                            Button(L10n("Cancelar")) {
                                                isEditingAIKey = false
                                                aiKeyInput = model.aiAPIKey
                                            }
                                            .buttonStyle(.plain)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Button {
                                            model.aiAPIKey = aiKeyInput
                                            isEditingAIKey = false
                                        } label: {
                                            Label(L10n("Salvar"), systemImage: "checkmark.circle.fill")
                                                .font(.system(size: 10, weight: .bold))
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                        .tint(.accentColor)
                                        .disabled(aiKeyInput.isEmpty)
                                    }
                                }
                                .onAppear {
                                    if aiKeyInput.isEmpty && hasKey {
                                        aiKeyInput = model.aiAPIKey
                                    }
                                }
                            }
                        }
                    }

                    if model.aiProvider != .none {
                        VStack(alignment: .leading, spacing: 4) {
                            Picker(L10n("Commit com IA"), selection: $model.commitMessageStyle) {
                                ForEach(CommitMessageStyle.allCases) { style in
                                    Text(style.label).tag(style)
                                }
                            }
                            .pickerStyle(.segmented)

                            Text(model.commitMessageStyle == .compact
                                ? L10n("commit.style.compact.hint")
                                : L10n("commit.style.detailed.hint"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

        }
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
    }

    private func pickCustomApp() {
        let panel = NSOpenPanel()
        panel.message = L10n("Selecione seu Terminal favorito")
        panel.allowedContentTypes = [.application, .aliasFile]
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            customTerminalPath = url.path
        } else {
            preferredTerminalRaw = ExternalTerminal.terminal.rawValue
        }
    }
}

private struct RecentProjectRow: View {
    let url: URL
    let isCurrent: Bool
    let changedCount: Int?
    let onTap: () -> Void
    @State private var isHovered = false

    private var rowBackground: Color {
        if isCurrent { return Color.white.opacity(0.10) }
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
                Spacer()

                if let count = changedCount, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }

                if isCurrent {
                    Circle()
                        .fill(DesignSystem.Colors.success)
                        .frame(width: 6, height: 6)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(rowBackground))
            .overlay(
                isCurrent ? RoundedRectangle(cornerRadius: 8).strokeBorder(DesignSystem.Colors.glassBorderDark, lineWidth: 1) : nil
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
        .onHover { h in isHovered = h }
    }
}
