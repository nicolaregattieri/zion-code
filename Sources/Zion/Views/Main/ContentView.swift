import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    private enum RootPresentation {
        case onboarding
        case welcome
        case workspace
    }

    private enum LaunchPhase {
        case bootstrapping
        case ready
    }

    enum NavigationEvent {
        case repositoryOpened
        case requestSection(AppSection)
        case showOnboardingFromHelp
        case navigateToGraph
        case navigateToCode
    }

    @State var model = RepositoryViewModel()
    @State private var launchPhase: LaunchPhase = .bootstrapping
    @State var selectedSection: AppSection = .code
    @State private var commitSearchQuery: String = ""
    @State private var selectedBranchTreeNodeID: String?
    @State private var isShortcutsVisible: Bool = false
    @State private var isHelpVisible: Bool = false
    @State private var shouldPresentOnboardingFromHelp: Bool = false
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .all
    @State private var isConflictResolverPromptVisible: Bool = false
    @State private var hasShownConflictResolverPromptForCurrentConflictState: Bool = false

    @AppStorage("zion.confirmationMode") var confirmationModeRaw: String = ConfirmationMode.destructiveOnly.rawValue
    @AppStorage("zion.uiLanguage") private var uiLanguageRaw: String = AppLanguage.system.rawValue
    @AppStorage("zion.appearance") private var appearanceRaw: String = AppAppearance.system.rawValue
    @AppStorage("zion.hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("zion.zenModeEnabled") private var zenModeEnabled: Bool = false
    @AppStorage("zion.zionModeEnabled") var zionModeEnabled: Bool = false
    @AppStorage("zion.preZionModeTheme") private var preZionModeTheme: String = ""

    private var uiLanguage: AppLanguage { AppLanguage(rawValue: uiLanguageRaw) ?? .system }
    private var appearance: AppAppearance { AppAppearance(rawValue: appearanceRaw) ?? .system }
    private var statusBarClearance: CGFloat { zenModeEnabled ? 0 : DesignSystem.Spacing.statusBarClearance }
    private var rootPresentation: RootPresentation {
        // Explicit replay from Help always wins.
        if shouldPresentOnboardingFromHelp {
            return .onboarding
        }
        // First-run only: show onboarding in Code section when there is no repo yet.
        if !hasCompletedOnboarding && model.repositoryURL == nil && selectedSection == .code {
            return .onboarding
        }
        if !model.openedFiles.isEmpty { return .workspace }
        if model.repositoryURL == nil || !model.isGitRepository {
            return .welcome
        }
        return .workspace
    }

    private let logger = DiagnosticLogger.shared

    func route(_ event: NavigationEvent) {
        switch event {
        case .repositoryOpened:
            hasCompletedOnboarding = true
            shouldPresentOnboardingFromHelp = false
            model.isBridgeVisible = false
            selectedSection = model.nextSectionAfterRepositoryOpen ?? .code
            model.nextSectionAfterRepositoryOpen = nil
        case .requestSection(let section):
            if zenModeEnabled && section != .code {
                model.isBridgeVisible = false
                selectedSection = .code
                return
            }
            guard section == .code || model.repositoryURL != nil else {
                model.statusMessage = L10n("Abra um repositorio para acessar %@", L10n(section.title))
                return
            }
            model.isBridgeVisible = false
            selectedSection = section
        case .showOnboardingFromHelp:
            isHelpVisible = false
            model.isBridgeVisible = false
            selectedSection = .code
            shouldPresentOnboardingFromHelp = true
        case .navigateToGraph:
            model.isBridgeVisible = false
            selectedSection = zenModeEnabled ? .code : .graph
        case .navigateToCode:
            model.isBridgeVisible = false
            selectedSection = .code
        }
    }

    var body: some View {
        ZStack {
            LiquidBackgroundView().ignoresSafeArea()

            NavigationSplitView(columnVisibility: $splitViewVisibility) {
                SidebarView(
                    model: model,
                    selectedSection: $selectedSection,
                    selectedBranchTreeNodeID: $selectedBranchTreeNodeID,
                    confirmationModeRaw: $confirmationModeRaw,
                    uiLanguageRaw: $uiLanguageRaw,
                    appearanceRaw: $appearanceRaw,
                    onOpen: { openRepositoryPanel() },
                    branchContextMenu: { branch in AnyView(branchContextMenu(for: branch)) }
                )
                .padding(.bottom, statusBarClearance)
            } detail: {
                // RIGID LAYOUT: Detail view is a solid container
                detailViewHost
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(!model.isRepositorySwitching)
                    .padding(.bottom, statusBarClearance)
                    .background(DesignSystem.Colors.background)
                    .overlay {
                        if model.isRepositorySwitching {
                            ZionLoadingOverlay()
                                .transition(.opacity)
                        }
                    }
            }
            .navigationSplitViewStyle(.balanced)
            .frame(minWidth: DesignSystem.Layout.windowMinWidth, minHeight: DesignSystem.Layout.windowMinHeight)
            .alert(L10n("Git não encontrado"), isPresented: $model.showGitNotFoundAlert) {
                Button(L10n("git.installCLT")) {
                    model.installCommandLineTools()
                }
                Button(L10n("git.checkAgain")) {
                    model.checkGitAvailability()
                }
                Button(L10n("Baixar Git")) {
                    if let url = URL(string: "https://git-scm.com/downloads") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button(L10n("OK"), role: .cancel) {}
            } message: {
                Text(L10n("git.notFound.message"))
            }
            .alert(L10n("Erro"), isPresented: Binding(get: { model.lastError != nil }, set: { show in if !show { model.lastError = nil } })) {
                Button(L10n("OK"), role: .cancel) {}
            } message: { Text(model.lastError ?? "") }
            .alert(L10n("push.warning.title"), isPresented: $model.showPushDivergenceWarning) {
                pushDivergenceAlertButtons
            } message: {
                switch model.pushDivergenceState {
                case .behind(let count):
                    Text(L10n("push.warning.behind", count))
                case .diverged(let ahead, let behind):
                    Text(L10n("push.warning.diverged", ahead, behind))
                case .clear:
                    Text("")
                }
            }
            .alert(L10n("conflicts.open.prompt.title"), isPresented: $isConflictResolverPromptVisible) {
                Button(L10n("conflicts.open.prompt.open")) {
                    model.loadConflictedFiles()
                    model.isConflictViewVisible = true
                }
                Button(L10n("Cancelar"), role: .cancel) {}
            } message: {
                Text(L10n("conflicts.open.prompt.message"))
            }
            .toolbar {
                if !zenModeEnabled {
                    mainToolbar
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !zenModeEnabled {
                    statusBar
                }
            }
            .background {
                // Cmd+1/2/3 tab switching (standard macOS convention)
                Group {
                    Button("") { route(.requestSection(.code)) }
                        .keyboardShortcut("1", modifiers: .command)
                    Button("") { route(.requestSection(.graph)) }
                        .keyboardShortcut("2", modifiers: .command)
                    Button("") { route(.requestSection(.operations)) }
                        .keyboardShortcut("3", modifiers: .command)
                    Button("") { isShortcutsVisible = true }
                        .keyboardShortcut("/", modifiers: .command)
                    Button("") {
                        if model.repositoryURL != nil {
                            model.isBranchReviewSheetVisible = false
                            model.isCodeReviewVisible = true
                        }
                    }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    Button("") {
                        withAnimation(DesignSystem.Motion.panel) {
                            zenModeEnabled.toggle()
                        }
                    }
                    .keyboardShortcut("J", modifiers: .command)
                    Button("") {
                        zionModeEnabled.toggle()
                    }
                    .keyboardShortcut("z", modifiers: [.command, .control])
                }
                .frame(width: 0, height: 0)
                .opacity(0)
            }
        }
        .id(uiLanguageRaw)
        .preferredColorScheme(zionModeEnabled ? .dark : appearance.colorScheme)
        .environment(\.locale, uiLanguage.locale)
        .environment(\.zionModeEnabled, zionModeEnabled)
        .onAppear {
            logger.log(.info, "Boot: starting", source: "ContentView")
            model.clipboardMonitor.start()
            model.restoreEditorSettings()
            let result = model.restoreLastRepository()
            switch result {
            case .opened(let url):
                hasCompletedOnboarding = true
                logger.log(.info, "Boot: restored \(url.lastPathComponent)", source: "ContentView")
            case .missing(let url):
                logger.log(.info, "Boot: missing \(url.lastPathComponent)", source: "ContentView")
            case .none:
                logger.log(.info, "Boot: no recent repo", source: "ContentView")
            }
            launchPhase = .ready
            if !AppDelegate.pendingOpenURLs.isEmpty {
                let urls = AppDelegate.pendingOpenURLs
                AppDelegate.pendingOpenURLs = []
                model.openExternalFiles(urls)
                selectedSection = .code
            }
            // Robust window activation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let window = NSApp.windows.first(where: { $0.isVisible }) {
                    window.makeKeyAndOrderFront(nil)
                }
                NSApp.activate(ignoringOtherApps: true)
            }
            splitViewVisibility = zenModeEnabled ? .detailOnly : .all
            if zenModeEnabled {
                selectedSection = .code
            }
        }
        .onDisappear {
            model.clipboardMonitor.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            model.syncSettingsFromDefaults()
        }
        .onChange(of: zenModeEnabled) { _, enabled in
            withAnimation(DesignSystem.Motion.panel) {
                splitViewVisibility = enabled ? .detailOnly : .all
                if enabled {
                    selectedSection = .code
                }
            }
        }
        .onChange(of: model.repositoryURL) { _, url in
            if url != nil {
                route(.repositoryOpened)
            }
        }
        .onChange(of: model.hasConflicts) { _, hasConflicts in
            guard hasConflicts else {
                hasShownConflictResolverPromptForCurrentConflictState = false
                isConflictResolverPromptVisible = false
                return
            }

            guard !hasShownConflictResolverPromptForCurrentConflictState, !model.isConflictViewVisible else {
                return
            }

            hasShownConflictResolverPromptForCurrentConflictState = true
            isConflictResolverPromptVisible = true
        }
        .onChange(of: model.isConflictViewVisible) { _, isVisible in
            if isVisible {
                hasShownConflictResolverPromptForCurrentConflictState = true
                isConflictResolverPromptVisible = false
            }
        }
        .onChange(of: selectedSection) { _, _ in
            if shouldPresentOnboardingFromHelp {
                return
            }
            // Onboarding should not block navigation: any section switch dismisses first-run onboarding.
            if !hasCompletedOnboarding {
                hasCompletedOnboarding = true
            }
        }
        .onChange(of: model.navigateToGraphRequested) { _, requested in
            if requested {
                route(.navigateToGraph)
                model.navigateToGraphRequested = false
            }
        }
        .onChange(of: model.navigateToCodeRequested) { _, requested in
            if requested {
                route(.navigateToCode)
                model.navigateToCodeRequested = false
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
        .sheet(isPresented: $model.isConflictViewVisible) {
            ConflictResolutionScreen(model: model)
        }
        .sheet(isPresented: $isShortcutsVisible) {
            KeyboardShortcutsSheet()
        }
        .sheet(isPresented: $isHelpVisible) {
            HelpSheet()
        }
        .sheet(isPresented: $model.isCodeReviewVisible) {
            CodeReviewSheet(model: model)
        }
        .sheet(isPresented: $model.isGitAuthPromptVisible) {
            if let context = model.gitAuthContext {
                GitAuthPromptSheet(
                    context: context,
                    onSubmit: { username, secret in
                        model.submitGitAuthPrompt(username: username, secret: secret)
                    },
                    onCancel: {
                        model.cancelGitAuthPrompt()
                    }
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showKeyboardShortcuts)) { _ in
            isShortcutsVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showHelp)) { _ in
            isHelpVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showOnboarding)) { _ in
            route(.showOnboardingFromHelp)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleZenMode)) { _ in
            withAnimation(DesignSystem.Motion.panel) {
                zenModeEnabled.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleZionMode)) { _ in
            zionModeEnabled.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFilesFromFinder)) { notification in
            guard let urls = notification.userInfo?["urls"] as? [URL] else { return }
            model.openExternalFiles(urls)
        }
        .onChange(of: zionModeEnabled) { oldValue, enabled in
            if enabled {
                preZionModeTheme = UserDefaults.standard.string(forKey: "editor.theme") ?? EditorTheme.dracula.rawValue
                UserDefaults.standard.set(EditorTheme.synthwave.rawValue, forKey: "editor.theme")
            } else if oldValue {
                // Only restore if explicitly toggled off (not auto-disabled by theme change)
                let currentTheme = UserDefaults.standard.string(forKey: "editor.theme") ?? ""
                if currentTheme == EditorTheme.synthwave.rawValue {
                    let restore = preZionModeTheme.isEmpty ? EditorTheme.dracula.rawValue : preZionModeTheme
                    UserDefaults.standard.set(restore, forKey: "editor.theme")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            // Auto-disable Zion Mode if user manually picks a different theme
            if zionModeEnabled {
                let currentTheme = UserDefaults.standard.string(forKey: "editor.theme") ?? ""
                if currentTheme != EditorTheme.synthwave.rawValue {
                    zionModeEnabled = false
                }
            }
        }
        .animation(DesignSystem.Motion.detail, value: model.isRepositorySwitching)
    }

    @ViewBuilder
    private var detailViewHost: some View {
        if launchPhase == .bootstrapping {
            Color.clear // Liquid background shows through during bootstrap
        } else if model.isBridgeVisible, model.repositoryURL != nil {
            BridgeScreen(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch rootPresentation {
            case .onboarding:
                ClimbingZionView(
                    model: model,
                    onComplete: {
                        hasCompletedOnboarding = true
                        shouldPresentOnboardingFromHelp = false
                    },
                    onOpen: {
                        hasCompletedOnboarding = true
                        shouldPresentOnboardingFromHelp = false
                        openRepositoryPanel()
                    },
                    onInit: {
                        hasCompletedOnboarding = true
                        shouldPresentOnboardingFromHelp = false
                        initRepositoryPanel()
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .welcome:
                WelcomeScreen(model: model, onOpen: { openRepositoryPanel() }, onInit: { initRepositoryPanel() })
            case .workspace:
                workspaceHost
            }
        }
    }

    private var workspaceHost: some View {
        ZStack {
            // CodeScreen is always rendered to keep terminal sessions alive
            CodeScreen(model: model, onOpenFolder: { openRepositoryPanel() }, isZenMode: zenModeEnabled)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(selectedSection == .code ? 1 : 0)
                .allowsHitTesting(selectedSection == .code)

            if selectedSection != .code {
                nonCodeContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
        }
        .animation(DesignSystem.Motion.panel, value: selectedSection)
    }

    @ViewBuilder
    private var nonCodeContent: some View {
        if model.repositoryURL == nil {
            WelcomeScreen(model: model, onOpen: { openRepositoryPanel() }, onInit: { initRepositoryPanel() })
        } else {
            ZStack {
                VStack(spacing: 0) {
                    if model.hasConflicts || model.isMerging || model.isRebasing || model.isCherryPicking {
                        conflictWarningBar
                            .zIndex(999)
                    }

                    if model.bisectPhase != .inactive {
                        BisectBanner(model: model)
                            .zIndex(998)
                            .transition(DesignSystem.Motion.slideFromTop)
                    }

                    nonCodeMainContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private var nonCodeMainContent: some View {
        switch selectedSection {
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


    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            ControlGroup {
                Button { openRepositoryPanel() } label: { Image(systemName: "folder") }
                    .help(L10n("Abrir repositório"))
                    .accessibilityLabel(L10n("Abrir repositório"))
                Button { model.isCloneSheetVisible = true } label: { Image(systemName: "square.and.arrow.down.on.square") }
                    .help(L10n("Clonar repositorio remoto"))
                    .accessibilityLabel(L10n("Clonar repositorio remoto"))
            }

            Button { model.refreshRepository() } label: { Image(systemName: "arrow.clockwise") }
                .disabled(model.repositoryURL == nil)
                .help(L10n("Atualizar status do repositório"))
                .accessibilityLabel(L10n("Atualizar status do repositório"))
                .keyboardShortcut("r", modifiers: .command)

            if model.repositoryURL != nil {
                ControlGroup {
                    Button { model.fetch() } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                        .help(L10n("Fetch: Busca atualizações remotas"))
                        .accessibilityLabel(L10n("Fetch: Busca atualizações remotas"))
                    Button { model.pull() } label: { Image(systemName: "arrow.down.to.line") }
                        .help(L10n("Pull: Puxa alterações da branch atual"))
                        .accessibilityLabel(L10n("Pull: Puxa alterações da branch atual"))
                    Button { model.requestPush() } label: { Image(systemName: "arrow.up.circle") }
                        .help(L10n("Push: Envia alterações locais"))
                        .accessibilityLabel(L10n("Push: Envia alterações locais"))
                }
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if model.repositoryURL != nil {
                ControlGroup {
                    Button {
                        withAnimation(DesignSystem.Motion.panel) {
                            zenModeEnabled = true
                        }
                    } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                        .help(L10n("zen.enter") + " (⇧⌘J)")
                        .accessibilityLabel(L10n("zen.enter"))
                    Button {
                        model.loadReflog()
                        model.isReflogVisible = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .help(L10n("Reflog / Desfazer"))
                    .accessibilityLabel(L10n("Reflog / Desfazer"))
                }

                Button {
                    model.isBridgeVisible = true
                } label: {
                    Image(systemName: "arrow.trianglehead.branch")
                }
                .help(L10n("bridge.open.hint"))
                .accessibilityLabel(L10n("bridge.open.hint"))
            }

            Button { isHelpVisible = true } label: { Image(systemName: "questionmark.circle") }
                .help(L10n("Conheca o Zion"))
                .accessibilityLabel(L10n("Conheca o Zion"))
        }
    }

    @ViewBuilder
    private var pushDivergenceAlertButtons: some View {
        switch model.pushDivergenceState {
        case .behind:
            Button(L10n("push.pullFirst")) { model.pull() }
            Button(L10n("Cancelar"), role: .cancel) {}
        case .diverged:
            Button(L10n("Rebase")) { model.pullRebase() }
            Button(L10n("push.forceWithLease")) { model.forceWithLeasePush() }
            Button(L10n("Cancelar"), role: .cancel) {}
        case .clear:
            Button(L10n("OK"), role: .cancel) {}
        }
    }

    private var conflictWarningBar: some View {
        HStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill").font(DesignSystem.Typography.sheetTitle).foregroundStyle(DesignSystem.Colors.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n("Conflitos")).font(DesignSystem.Typography.sheetTitle)
                Text(L10n("conflicts.banner.subtitle")).font(DesignSystem.Typography.label).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                Button {
                    model.loadConflictedFiles()
                    model.isConflictViewVisible = true
                } label: {
                    Label(L10n("Resolver no Zion"), systemImage: "hammer.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.warning)
                .controlSize(.small)

                if model.isMerging { Button(L10n("Abort")) { model.abortMerge() }.buttonStyle(.bordered).controlSize(.small) }
                if model.isRebasing { Button(L10n("Abort")) { model.abortRebase() }.buttonStyle(.bordered).controlSize(.small) }
            }
        }
        .padding(16)
        .background(DesignSystem.Colors.background)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func openRepositoryPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        if panel.runModal() == .OK, let selectedURL = panel.url { model.openRepository(selectedURL) }
    }

    private func initRepositoryPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.prompt = L10n("Inicializar Repositorio")
        if panel.runModal() == .OK, let selectedURL = panel.url {
            model.repositoryURL = selectedURL
            model.initRepository()
        }
    }

}
