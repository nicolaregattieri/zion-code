import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: RepositoryViewModel
    @Binding var selectedSection: AppSection?
    @Binding var selectedBranchTreeNodeID: String?
    @Binding var confirmationModeRaw: String
    @Binding var inferBranchOrigins: Bool
    @Binding var uiLanguageRaw: String
    
    @AppStorage("zion.preferredEditor") private var preferredEditorRaw: String = ExternalEditor.vscode.rawValue
    @AppStorage("zion.preferredTerminal") private var preferredTerminalRaw: String = ExternalTerminal.terminal.rawValue
    @AppStorage("zion.customEditorPath") private var customEditorPath: String = ""
    @AppStorage("zion.customTerminalPath") private var customTerminalPath: String = ""
    
    let onOpen: () -> Void
    let onOpenInEditor: () -> Void
    let onOpenInTerminal: () -> Void
    let branchContextMenu: (String) -> AnyView
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                repoSummaryCard
                
                // ACTIONS CARD - ALWAYS AT THE TOP IF REPO OPEN
                if model.repositoryURL != nil {
                    GlassCard(spacing: 12) {
                        Text(L10n("Acoes Rapidas")).font(.headline).foregroundStyle(.primary)
                        HStack(spacing: 8) {
                            actionButton(title: "Fetch", icon: "arrow.down.circle", color: .blue, action: model.fetch)
                            actionButton(title: "Pull", icon: "arrow.down.to.line", color: .green, action: model.pull)
                            actionButton(title: "Push", icon: "arrow.up.circle", color: .orange, action: model.push)
                            actionButton(title: "Atualizar", icon: "arrow.clockwise", color: .secondary, action: model.refreshRepository)
                        }
                    }
                    .padding(.horizontal, 10)
                }
                
                workspaceCard

                if model.repositoryURL != nil {
                    quickAccessCard
                }

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
    }

    private var repoSummaryCard: some View {
        GlassCard(spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(LinearGradient(colors: [Color.teal, Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
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
                        title: isDetached ? "HEAD" : "Branch", 
                        value: model.currentBranch, 
                        tint: isDetached ? .orange : .green, 
                        icon: isDetached ? "anchor" : "crown.fill"
                    )
                    StatusChip(title: "Commit", value: model.headShortHash, tint: .blue, icon: "number")
                }
            }
        }.padding(.horizontal, 10)
    }

    private var quickAccessCard: some View {
        GlassCard(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n("Abrir Externamente")).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                Text(L10n("Abrir o repositorio no seu editor ou terminal favorito.")).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button(action: onOpenInEditor) {
                    Label(L10n("Editor de Codigo"), systemImage: "chevron.left.forwardslash.chevron.right").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered).controlSize(.large)

                Button(action: onOpenInTerminal) {
                    Label(L10n("Terminal"), systemImage: "terminal").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered).controlSize(.large)
            }
        }.padding(.horizontal, 10)
    }

    private var nonCurrentWorktrees: [WorktreeItem] {
        model.worktrees.filter { !$0.isCurrent }
    }

    private var worktreesCard: some View {
        GlassCard(spacing: 10) {
            HStack {
                Text(L10n("Worktrees")).font(.headline)
                Spacer()
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
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func actionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(color)
                }
                if !title.isEmpty {
                    Text(L10n(title))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var workspaceCard: some View {
        GlassCard(spacing: 8) {
            Text(L10n("Workspace")).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
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
                }
            }
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(isSelected ? Color.primary.opacity(0.08) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Color.primary.opacity(0.15) : Color.clear, lineWidth: 1))
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private var sidebarBranchExplorer: some View {
        GlassCard(spacing: 0) {
            HStack {
                Text(L10n("Branches")).font(.headline)
                Spacer()
                Text("\(model.branchInfos.count) \(L10n("refs"))").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
            Divider()
            if model.branchTree.isEmpty {
                VStack(spacing: 8) { Image(systemName: "arrow.triangle.branch").font(.title2).foregroundStyle(.secondary); Text(L10n("Sem branches detectadas")).font(.headline) }.frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    List(selection: $selectedBranchTreeNodeID) {
                        ForEach(model.branchTree) { root in
                            OutlineGroup([root], children: \.outlineChildren) { node in
                                branchTreeNodeRow(node).tag(node.id)
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .controlSize(.small)
                    .frame(minWidth: 500)
                }.frame(minHeight: 120, maxHeight: 250)
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
                        if isCurrent { Text("current").font(.system(size: 8, weight: .bold)).padding(.horizontal, 4).padding(.vertical, 1).background(Color.accentColor.opacity(0.2)).foregroundStyle(Color.accentColor).clipShape(Capsule()) }
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
            Text(L10n("Configuracoes")).font(.headline).frame(maxWidth: .infinity, alignment: .leading)

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

                // Editor
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n("Editor de Codigo")).font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $preferredEditorRaw) {
                        ForEach(ExternalEditor.allCases) { editor in
                            Text(editor.label).tag(editor.rawValue)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: preferredEditorRaw) { val in
                        if val == "custom" { pickCustomApp(forEditor: true) }
                    }
                    if preferredEditorRaw == "custom" && !customEditorPath.isEmpty {
                        Text(URL(fileURLWithPath: customEditorPath).lastPathComponent)
                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                    }
                }
                
                // Terminal
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n("Terminal")).font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $preferredTerminalRaw) {
                        ForEach(ExternalTerminal.allCases) { term in
                            Text(term.label).tag(term.rawValue)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: preferredTerminalRaw) { val in
                        if val == "custom" { pickCustomApp(forEditor: false) }
                    }
                    if preferredTerminalRaw == "custom" && !customTerminalPath.isEmpty {
                        Text(URL(fileURLWithPath: customTerminalPath).lastPathComponent)
                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                    }
                }
            }
            .pickerStyle(.menu)

            Divider().opacity(0.1)

            HStack(spacing: 4) {
                Toggle(L10n("Inferir origem da arvore (best practice)"), isOn: $inferBranchOrigins)
                    .toggleStyle(.switch).font(.caption)
                
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help(L10n("Tenta detectar automaticamente de qual branch cada uma foi criada para organizar a arvore lateral de forma hierarquica. Recomendado para repositorios com muitas branches."))
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
    }

    private func pickCustomApp(forEditor: Bool) {
        let panel = NSOpenPanel()
        panel.message = forEditor ? "Selecione seu Editor de Codigo favorito" : "Selecione seu Terminal favorito"
        panel.allowedContentTypes = [.application, .aliasFile]
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            if forEditor { customEditorPath = url.path } else { customTerminalPath = url.path }
        } else {
            if forEditor { preferredEditorRaw = ExternalEditor.vscode.rawValue }
            else { preferredTerminalRaw = ExternalTerminal.terminal.rawValue }
        }
    }
}
