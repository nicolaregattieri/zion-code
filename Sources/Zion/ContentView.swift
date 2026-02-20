import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var model = RepositoryViewModel()
    @State private var selectedSection: AppSection? = .code
    @State private var commitSearchQuery: String = ""
    @State private var selectedBranchTreeNodeID: String?
    @State private var isShortcutsVisible: Bool = false
    @State private var isHelpVisible: Bool = false
    
    @AppStorage("zion.confirmationMode") private var confirmationModeRaw: String = ConfirmationMode.destructiveOnly.rawValue
    @AppStorage("zion.uiLanguage") private var uiLanguageRaw: String = AppLanguage.system.rawValue
    @AppStorage("zion.preferredTerminal") private var preferredTerminalRaw: String = ExternalTerminal.terminal.rawValue
    @AppStorage("zion.customTerminalPath") private var customTerminalPath: String = ""
    
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
                    uiLanguageRaw: $uiLanguageRaw,
                    onOpen: { openRepositoryPanel() },
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
            .alert(L10n("Erro"), isPresented: Binding(get: { model.lastError != nil }, set: { show in if !show { model.lastError = nil } })) {
                Button(L10n("OK"), role: .cancel) {}
            } message: { Text(model.lastError ?? "") }
            .toolbar { mainToolbar }
            .safeAreaInset(edge: .bottom) { statusBar }
            .background {
                // Cmd+1/2/3 tab switching (standard macOS convention)
                Group {
                    Button("") { selectedSection = .code }
                        .keyboardShortcut("1", modifiers: .command)
                    Button("") { selectedSection = .graph }
                        .keyboardShortcut("2", modifiers: .command)
                    Button("") { selectedSection = .operations }
                        .keyboardShortcut("3", modifiers: .command)
                    Button("") { isShortcutsVisible = true }
                        .keyboardShortcut("/", modifiers: .command)
                }
                .frame(width: 0, height: 0)
                .opacity(0)
            }
        }
        .id(uiLanguageRaw) 
        .environment(\.locale, uiLanguage.locale)
        .onAppear {
            model.restoreEditorSettings()
            // Robust window activation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let window = NSApp.windows.first(where: { $0.isVisible }) {
                    window.makeKeyAndOrderFront(nil)
                }
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .onChange(of: model.repositoryURL) { _, url in
            if url != nil {
                selectedSection = .code
            }
        }
        .onChange(of: model.navigateToGraphRequested) { _, requested in
            if requested {
                selectedSection = .graph
                model.navigateToGraphRequested = false
            }
        }
        .sheet(isPresented: $model.isReflogVisible) {
            ReflogSheet(model: model)
        }
        .sheet(isPresented: $model.isRebaseSheetVisible) {
            InteractiveRebaseSheet(model: model)
        }
        .sheet(isPresented: $model.isPRSheetVisible) {
            PullRequestSheet(model: model)
        }
        .sheet(isPresented: $model.isCloneSheetVisible) {
            CloneSheet(model: model)
        }
        .sheet(isPresented: $isShortcutsVisible) {
            KeyboardShortcutsSheet()
        }
        .sheet(isPresented: $isHelpVisible) {
            HelpSheet()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showKeyboardShortcuts)) { _ in
            isShortcutsVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showHelp)) { _ in
            isHelpVisible = true
        }
    }

    @ViewBuilder
    private var detailViewHost: some View {
        ZStack {
            // CodeScreen is always rendered to keep terminal sessions alive
            CodeScreen(model: model, onOpenFolder: { openRepositoryPanel() })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(selectedSection == .code ? 1 : 0)
                .allowsHitTesting(selectedSection == .code)

            if selectedSection != .code {
                nonCodeContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var nonCodeContent: some View {
        if model.repositoryURL == nil {
            WelcomeScreen(model: model) { openRepositoryPanel() }
        } else if !model.isGitRepository {
            nonGitDirectoryView
        } else {
            VStack(spacing: 0) {
                if model.hasConflicts || model.isMerging || model.isRebasing || model.isCherryPicking {
                    conflictWarningBar
                        .zIndex(999)
                }

                nonCodeMainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var nonCodeMainContent: some View {
        switch selectedSection ?? .graph {
        case .graph:
            GraphScreen(
                model: model,
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
        case .code:
            EmptyView() // Handled by ZStack above
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


    private var mainToolbar: ToolbarItemGroup<some View> {
        ToolbarItemGroup(placement: .navigation) {
            ControlGroup {
                Button { openRepositoryPanel() } label: { Image(systemName: "folder") }
                    .help(L10n("Abrir repositório"))

                Button { model.isCloneSheetVisible = true } label: { Image(systemName: "square.and.arrow.down.on.square") }
                    .help(L10n("Clonar repositorio remoto"))

                Button { model.refreshRepository() } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(model.repositoryURL == nil)
                    .help(L10n("Atualizar status do repositório"))
            }
            
            if model.repositoryURL != nil {
                ControlGroup {
                    Button { model.fetch() } label: { Image(systemName: "arrow.down.circle") }
                        .help(L10n("Fetch: Busca atualizações remotas"))
                    
                    Button { model.pull() } label: { Image(systemName: "arrow.down.to.line") }
                        .help(L10n("Pull: Puxa alterações da branch atual"))
                    
                    Button { model.push() } label: { Image(systemName: "arrow.up.circle") }
                        .help(L10n("Push: Envia alterações locais"))
                }
                
                ControlGroup {
                    Button { openRepositoryInTerminal() } label: { Image(systemName: "terminal") }
                        .help(L10n("Abrir Terminal"))
                }

                ControlGroup {
                    Button {
                        model.loadReflog()
                        model.isReflogVisible = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .help(L10n("Reflog / Desfazer"))
                }
            }

            Button { isHelpVisible = true } label: { Image(systemName: "questionmark.circle") }
                .help(L10n("Conheca o Zion"))
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
            HStack(spacing: 8) {
                if model.isMerging { Button(L10n("Abort")) { model.abortMerge() }.buttonStyle(.bordered) }
                if model.isRebasing { Button(L10n("Abort")) { model.abortRebase() }.buttonStyle(.bordered) }
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
        let isStash = commit.decorations.contains { $0.contains("refs/stash") }
        
        if isStash {
            Button(L10n("Apply Stash")) {
                performGitAction(title: L10n("Apply Stash"), message: L10n("Aplicar as mudancas deste stash na branch atual?"), destructive: false) {
                    model.selectedStash = commit.id // Use the hash
                    model.applySelectedStash()
                }
            }
            Button(L10n("Pop Stash")) {
                performGitAction(title: L10n("Pop Stash"), message: L10n("Aplicar as mudancas deste stash e REMOVER da lista?"), destructive: false) {
                    model.selectedStash = commit.id // Use the hash
                    model.popSelectedStash()
                }
            }
            Divider()
            Button(L10n("Drop Stash"), role: .destructive) {
                performGitAction(title: L10n("Drop Stash"), message: L10n("Remover permanentemente este stash?"), destructive: true) {
                    model.selectedStash = commit.id // Use the hash
                    model.dropSelectedStash()
                }
            }
            Divider()
            Button(L10n("Checkout Stash (Inspecionar)")) {
                model.checkout(reference: commit.id)
            }
        } else {
            Button(L10n("Reset Branch to here (Soft)")) { 
                performGitAction(title: L10n("Reset --soft"), message: L10n("Resetar a branch atual para este commit mantendo as mudancas no stage?"), destructive: true) {
                    model.resetToCommit(commit.id, hard: false)
                }
            }
            Button(L10n("Reset Branch to here (Hard)"), role: .destructive) { 
                performGitAction(title: L10n("Reset --hard"), message: L10n("AVISO: Isso apagara todas as mudancas nao salvas. Continuar?"), destructive: true) {
                    model.resetToCommit(commit.id, hard: true)
                }
            }
            Divider()
            Button(L10n("Adicionar Tag...")) { if let name = promptForText(title: L10n("Nova tag"), message: L10n("Nome:"), defaultValue: "v") { model.createTag(named: name, at: commit.id) } }
            Button(L10n("Criar Branch...")) { if let res = promptForBranchCreation(from: commit.shortHash) { model.createBranch(named: res.name, from: commit.id, andCheckout: res.checkout) } }
            Divider()
            Button(L10n("Cherry-pick")) {
                performGitAction(title: L10n("Cherry-pick"), message: L10n("Aplicar este commit na branch atual?"), destructive: false) {
                    model.cherryPick(commitHash: commit.id)
                }
            }
            Button(L10n("Revert")) {
                performGitAction(title: L10n("Revert"), message: L10n("Reverter este commit criando um novo commit?"), destructive: false) {
                    model.revert(commitHash: commit.id)
                }
            }
            Divider()
            Button(L10n("Rebase Interativo a partir daqui...")) {
                model.prepareInteractiveRebase(from: commit.id)
            }
        }
        
        Divider()
        Button(L10n("Copiar Assunto")) { copyToPasteboard(commit.subject) }
        Button(L10n("Copiar Hash")) { copyToPasteboard(commit.id) }
    }

    @ViewBuilder
    private func branchContextMenu(for branch: String) -> some View {
        Button(L10n("Copiar Nome da Branch")) { copyToPasteboard(branch) }
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
        
        if !isRemote {
            Button(L10n("Criar Pull Request...")) {
                model.isPRSheetVisible = true
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
                Color(red: 0.05, green: 0.02, blue: 0.10).ignoresSafeArea()
                Circle().fill(Color.purple.opacity(0.15)).frame(width: 520).blur(radius: 80).offset(x: -340, y: -220)
                Circle().fill(Color.indigo.opacity(0.12)).frame(width: 420).blur(radius: 70).offset(x: 280, y: -280)
            } else {
                Color(red: 0.96, green: 0.94, blue: 1.00).ignoresSafeArea()
                Circle().fill(Color.purple.opacity(0.10)).frame(width: 520).blur(radius: 80).offset(x: -340, y: -220)
            }
        }
    }
}
