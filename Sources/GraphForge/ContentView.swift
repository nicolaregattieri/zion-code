import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = RepositoryViewModel()
    @State private var selectedSection: AppSection? = .graph
    @State private var commitSearchQuery: String = ""
    @State private var selectedBranchTreeNodeID: String?
    
    @AppStorage("graphforge.confirmationMode") private var confirmationModeRaw: String = ConfirmationMode.destructiveOnly.rawValue
    @AppStorage("graphforge.uiLanguage") private var uiLanguageRaw: String = AppLanguage.system.rawValue
    @AppStorage("graphforge.preferredEditor") private var preferredEditorRaw: String = ExternalEditor.vscode.rawValue
    @AppStorage("graphforge.preferredTerminal") private var preferredTerminalRaw: String = ExternalTerminal.terminal.rawValue
    @AppStorage("graphforge.customEditorPath") private var customEditorPath: String = ""
    @AppStorage("graphforge.customTerminalPath") private var customTerminalPath: String = ""
    @AppStorage("graphforge.inferBranchOrigins") private var inferBranchOrigins: Bool = false
    
    private let topChromePadding: CGFloat = 34
    private var uiLanguage: AppLanguage { AppLanguage(rawValue: uiLanguageRaw) ?? .system }

    var body: some View {
        ZStack {
            LiquidBackgroundView().ignoresSafeArea()

            NavigationSplitView {
                SidebarView(
                    model: model,
                    selectedSection: $selectedSection,
                    selectedBranchTreeNodeID: $selectedBranchTreeNodeID,
                    confirmationModeRaw: $confirmationModeRaw,
                    inferBranchOrigins: $inferBranchOrigins,
                    uiLanguageRaw: $uiLanguageRaw,
                    onOpen: { model.repositoryURL = nil },
                    onOpenInEditor: { openRepositoryInEditor() },
                    onOpenInTerminal: { openRepositoryInTerminal() },
                    branchContextMenu: { branch in AnyView(branchContextMenu(for: branch)) }
                )
            } detail: {
                // RIGID LAYOUT: Detail view is a solid container
                detailViewHost
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.windowBackgroundColor)) 
            }
            .navigationSplitViewStyle(.balanced)
            .frame(minWidth: 1360, minHeight: 840)
            .padding(.top, topChromePadding)
            .alert(L10n("Erro"), isPresented: Binding(get: { model.lastError != nil }, set: { show in if !show { model.lastError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(model.lastError ?? "") }
            .toolbar { mainToolbar }
            .safeAreaInset(edge: .bottom) { statusBar }
        }
        .id(uiLanguageRaw) 
        .environment(\.locale, uiLanguage.locale)
        .onAppear { model.setInferBranchOrigins(inferBranchOrigins) }
        .onChange(of: inferBranchOrigins) { enabled in model.setInferBranchOrigins(enabled) }
    }

    @ViewBuilder
    private var detailViewHost: some View {
        if model.repositoryURL == nil {
            WelcomeScreen(model: model) { openRepositoryPanel() }
        } else if !model.isGitRepository {
            nonGitDirectoryView
        } else {
            VStack(spacing: 0) {
                if model.hasConflicts || model.isMerging || model.isRebasing || model.isCherryPicking {
                    conflictWarningBar
                        .zIndex(999) // Stay on top
                }
                
                mainContentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var nonGitDirectoryView: some View {
        VStack(spacing: 32) {
            VStack(spacing: 16) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                Text(L10n("Nao e um repositorio Git"))
                    .font(.title.bold())
                Text(L10n("Este diretorio nao possui um repositorio Git inicializado."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 16) {
                Button {
                    model.initRepository()
                } label: {
                    Label(L10n("Inicializar Repositorio"), systemImage: "plus.square.fill")
                        .frame(width: 240)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    model.repositoryURL = nil
                } label: {
                    Text(L10n("Voltar"))
                        .frame(width: 240)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var mainContentArea: some View {
        switch selectedSection ?? .graph {
        case .graph:
            GraphScreen(
                model: model,
                selectedSection: $selectedSection,
                commitSearchQuery: $commitSearchQuery,
                performGitAction: { t, m, d, a in performGitAction(title: t, message: m, destructive: d, action: a) },
                commitContextMenu: { commit in AnyView(commitContextMenu(for: commit)) },
                branchContextMenu: { branch in AnyView(branchContextMenu(for: branch)) },
                tagContextMenu: { tag in AnyView(tagContextMenu(for: tag)) }
            )
        case .operations:
            OperationsScreen(
                model: model,
                performGitAction: { t, m, d, a in performGitAction(title: t, message: m, destructive: d, action: a) },
                branchContextMenu: { branch in AnyView(branchContextMenu(for: branch)) }
            )
        case .worktrees:
            WorktreesScreen(
                model: model,
                performGitAction: { t, m, d, a in performGitAction(title: t, message: m, destructive: d, action: a) }
            )
        }
    }

    private var mainToolbar: ToolbarItemGroup<some View> {
        ToolbarItemGroup(placement: .navigation) {
            Button { model.repositoryURL = nil } label: { Label(L10n("Abrir"), systemImage: "folder") }
            Button { model.refreshRepository() } label: { Label(L10n("Atualizar"), systemImage: "arrow.clockwise") }.disabled(model.repositoryURL == nil)
            
            if model.repositoryURL != nil {
                Divider()
                Button { model.fetch() } label: { Label(L10n("Fetch"), systemImage: "arrow.down.circle") }
                Button { model.pull() } label: { Label(L10n("Pull"), systemImage: "arrow.down.and.line.horizontal") }
                Button { model.push() } label: { Label(L10n("Push"), systemImage: "arrow.up.circle") }
                
                Divider()
                Button { openRepositoryInEditor() } label: { Label(L10n("Editor de Codigo"), systemImage: "chevron.left.forwardslash.chevron.right") }
                Button { openRepositoryInTerminal() } label: { Label(L10n("Terminal"), systemImage: "terminal") }
            }
        }
    }

    private var conflictWarningBar: some View {
        HStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill").font(.title3).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n("Conflitos")).font(.headline)
                Text(L10n("Resolva os conflitos na sua IDE favorita.")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: { openRepositoryInEditor(conflictMode: true) }) {
                Label(L10n("Resolver na IDE"), systemImage: "wand.and.stars")
            }.buttonStyle(.borderedProminent).tint(.orange)
            
            HStack(spacing: 8) {
                if model.isMerging { Button("Abort") { model.abortMerge() }.buttonStyle(.bordered) }
                if model.isRebasing { Button("Abort") { model.abortRebase() }.buttonStyle(.bordered) }
            }
        }
        .padding(16)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            if model.isBusy { ProgressView().controlSize(.small) }
            Text(model.statusMessage).lineLimit(1).font(.caption).foregroundStyle(.secondary)
            Spacer()
            if let repositoryURL = model.repositoryURL {
                Text(repositoryURL.path).lineLimit(1).font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary)
            }
        }.padding(.horizontal, 16).padding(.vertical, 8).background(.ultraThinMaterial).overlay(alignment: .top) { Divider().opacity(0.45) }
    }

    private func openRepositoryInEditor(conflictMode: Bool = false) {
        guard let url = model.repositoryURL else { return }
        let editor = ExternalEditor(rawValue: preferredEditorRaw) ?? .vscode
        
        let appPath: String
        if editor == .custom {
            appPath = customEditorPath
        } else {
            // Use common paths for reliability
            switch editor {
            case .vscode: appPath = "/Applications/Visual Studio Code.app"
            case .cursor: appPath = "/Applications/Cursor.app"
            case .antigravity: appPath = "/Applications/Antigravity.app"
            case .xcode: appPath = "/Applications/Xcode.app"
            case .sublime: appPath = "/Applications/Sublime Text.app"
            default: appPath = ""
            }
        }

        let ws = NSWorkspace.shared
        
        // Strategy 1: CLI Merge Tool (for VS Code/Cursor)
        if conflictMode && (editor == .vscode || editor == .cursor) {
            let binName = editor == .vscode ? "code" : "cursor"
            let internalBin = "\(appPath)/Contents/Resources/app/bin/\(binName)"
            if FileManager.default.fileExists(atPath: internalBin) {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: internalBin)
                task.arguments = ["--merge", url.path]
                try? task.run()
                return
            }
        }

        // Strategy 2: NSWorkspace open with App URL
        if !appPath.isEmpty, let appUrl = URL(string: "file://\(appPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")") {
            ws.open([url], withApplicationAt: appUrl, configuration: NSWorkspace.OpenConfiguration())
        } else {
            // Strategy 3: Bundle ID fallback
            if let appUrl = ws.urlForApplication(withBundleIdentifier: editor.id) {
                ws.open([url], withApplicationAt: appUrl, configuration: NSWorkspace.OpenConfiguration())
            } else {
                ws.open(url) // Final fallback: Finder
            }
        }
    }

    private func openRepositoryInTerminal() {
        guard let url = model.repositoryURL else { return }
        let terminal = ExternalTerminal(rawValue: preferredTerminalRaw) ?? .terminal
        let ws = NSWorkspace.shared
        
        let appPath: String = (terminal == .custom) ? customTerminalPath : {
            switch terminal {
            case .terminal: return "/System/Applications/Utilities/Terminal.app"
            case .iterm: return "/Applications/iTerm.app"
            case .warp: return "/Applications/Warp.app"
            default: return ""
            }
        }()

        if !appPath.isEmpty, let appUrl = URL(string: "file://\(appPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")") {
            ws.open([url], withApplicationAt: appUrl, configuration: NSWorkspace.OpenConfiguration())
        } else if let appUrl = ws.urlForApplication(withBundleIdentifier: terminal.id) {
            ws.open([url], withApplicationAt: appUrl, configuration: NSWorkspace.OpenConfiguration())
        } else {
            ws.open(url)
        }
    }

    private func performGitAction(title: String, message: String, destructive: Bool = false, action: @escaping () -> Void) {
        if shouldConfirmAction(destructive: destructive) {
            let alert = NSAlert()
            alert.alertStyle = destructive ? .warning : .informational
            alert.messageText = title; alert.informativeText = message
            alert.addButton(withTitle: destructive ? L10n("Confirmar") : L10n("Continuar")); alert.addButton(withTitle: L10n("Cancelar"))
            if alert.runModal() != .alertFirstButtonReturn { return }
        }
        action()
    }

    private func shouldConfirmAction(destructive: Bool) -> Bool {
        let mode = ConfirmationMode(rawValue: confirmationModeRaw) ?? .destructiveOnly
        switch mode {
        case .never: return false
        case .destructiveOnly: return destructive
        case .all: return true
        }
    }

    @ViewBuilder
    private func commitContextMenu(for commit: Commit) -> some View {
        Button(L10n("Adicionar Tag...")) { if let name = promptForText(title: L10n("Nova tag"), message: L10n("Nome:"), defaultValue: "v") { model.createTag(named: name, at: commit.id) } }
        Button(L10n("Criar Branch...")) { if let res = promptForBranchCreation(from: commit.shortHash) { model.createBranch(named: res.name, from: commit.id, andCheckout: res.checkout) } }
        Divider()
        Button(L10n("Abrir no Editor")) { openRepositoryInEditor() }
        Divider()
        Button(L10n("Copiar Hash")) { copyToPasteboard(commit.id) }
    }

    @ViewBuilder
    private func branchContextMenu(for branch: String) -> some View {
        Button(L10n("Checkout & Abrir no Editor")) { 
            model.checkout(reference: branch)
            openRepositoryInEditor()
        }
        Divider()
        Button(L10n("Checkout")) { model.checkout(reference: branch) }
        
        let info = model.branchInfo(named: branch)
        let isRemote = info?.isRemote ?? (branch.contains("/") && !branch.hasPrefix("feature/") && !branch.hasPrefix("bugfix/"))
        
        if isRemote {
            Button(L10n("Pull")) { model.pullIntoCurrent(fromRemoteBranch: branch) }
        } else if let upstream = info?.upstream, !upstream.isEmpty {
            Button(L10n("Pull")) { model.pullIntoCurrent(fromRemoteBranch: upstream) }
        }

        Button(L10n("Merge")) { 
            performGitAction(title: L10n("Merge"), message: L10n("Fazer merge da branch informada na atual?"), destructive: false) {
                model.mergeBranch(named: branch) 
            }
        }
        Button(L10n("Rebase")) {
            performGitAction(title: L10n("Rebase"), message: L10n("Rebasear a branch atual no target informado?"), destructive: true) {
                model.rebaseCurrentBranch(onto: branch)
            }
        }
        Divider()
        Button(L10n("New Branch")) {
            if let res = promptForBranchCreation(from: branch) {
                model.createBranch(named: res.name, from: branch, andCheckout: res.checkout)
            }
        }
        Divider()
        
        if isRemote {
            Button(L10n("Remover branch remota"), role: .destructive) {
                performGitAction(title: L10n("Remover branch remota"), message: String(format: L10n("Deseja remover permanentemente a branch remota %@?"), branch), destructive: true) {
                    model.deleteRemoteBranch(reference: branch)
                }
            }
        } else {
            Button(L10n("Push to Remote")) {
                model.pushBranch(branch, to: "origin", setUpstream: true, mode: .normal)
            }
            Divider()
            Button(L10n("Remover branch local"), role: .destructive) {
                performGitAction(title: L10n("Remover branch local"), message: String(format: L10n("Deseja remover a branch local %@?"), branch), destructive: true) {
                    model.deleteLocalBranch(branch, force: false)
                }
            }
            Button(L10n("Remover branch local (Force)"), role: .destructive) {
                performGitAction(title: L10n("Remover branch local (Force)"), message: String(format: L10n("Deseja remover FORCADO a branch local %@?"), branch), destructive: true) {
                    model.deleteLocalBranch(branch, force: true)
                }
            }
        }
    }

    @ViewBuilder
    private func tagContextMenu(for tag: String) -> some View {
        Button(L10n("Remover tag"), role: .destructive) {
            performGitAction(title: L10n("Remover tag"), message: String(format: L10n("Deseja remover a tag informada?"), tag), destructive: true) {
                model.tagInput = tag
                model.deleteTag()
            }
        }
    }

    private func openRepositoryPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        if panel.runModal() == .OK, let selectedURL = panel.url { model.openRepository(selectedURL) }
    }

    private func copyToPasteboard(_ value: String) {
        let pb = NSPasteboard.general; pb.clearContents(); pb.setString(value, forType: .string)
    }

    private func promptForText(title: String, message: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title; alert.informativeText = message
        alert.addButton(withTitle: L10n("OK")); alert.addButton(withTitle: L10n("Cancelar"))
        let field = NSTextField(string: defaultValue)
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24); alert.accessoryView = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    private func promptForBranchCreation(from source: String) -> (name: String, checkout: Bool)? {
        let alert = NSAlert()
        alert.messageText = L10n("Nova branch")
        alert.informativeText = L10n("Nome da branch a partir de %@", source)
        alert.addButton(withTitle: L10n("Criar")); alert.addButton(withTitle: L10n("Cancelar"))
        let field = NSTextField(string: "feature/")
        let check = NSButton(checkboxWithTitle: L10n("Fazer checkout"), target: nil, action: nil); check.state = .on
        let stack = NSStackView(views: [field, check]); stack.orientation = .vertical; stack.alignment = .leading; stack.frame = NSRect(x: 0, y: 0, width: 320, height: 60); alert.accessoryView = stack
        return alert.runModal() == .alertFirstButtonReturn ? (field.stringValue, check.state == .on) : nil
    }
}

struct LiquidBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ZStack {
            if colorScheme == .dark {
                Color(red: 0.04, green: 0.08, blue: 0.12).ignoresSafeArea()
                Circle().fill(Color.teal.opacity(0.22)).frame(width: 520).blur(radius: 60).offset(x: -340, y: -220)
                Circle().fill(Color.blue.opacity(0.26)).frame(width: 420).blur(radius: 56).offset(x: 280, y: -280)
            } else {
                Color(red: 0.93, green: 0.97, blue: 1.00).ignoresSafeArea()
                Circle().fill(Color.teal.opacity(0.22)).frame(width: 520).blur(radius: 64).offset(x: -340, y: -220)
            }
        }
    }
}
