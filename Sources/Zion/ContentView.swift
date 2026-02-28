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

    private enum NavigationEvent {
        case repositoryOpened
        case requestSection(AppSection)
        case showOnboardingFromHelp
        case navigateToGraph
        case navigateToCode
    }

    @State private var model = RepositoryViewModel()
    @State private var launchPhase: LaunchPhase = .bootstrapping
    @State private var selectedSection: AppSection = .code
    @State private var commitSearchQuery: String = ""
    @State private var selectedBranchTreeNodeID: String?
    @State private var isShortcutsVisible: Bool = false
    @State private var isHelpVisible: Bool = false
    @State private var shouldPresentOnboardingFromHelp: Bool = false
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .all

    @AppStorage("zion.confirmationMode") private var confirmationModeRaw: String = ConfirmationMode.destructiveOnly.rawValue
    @AppStorage("zion.uiLanguage") private var uiLanguageRaw: String = AppLanguage.system.rawValue
    @AppStorage("zion.appearance") private var appearanceRaw: String = AppAppearance.system.rawValue
    @AppStorage("zion.hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("zion.zenModeEnabled") private var zenModeEnabled: Bool = false
    @AppStorage("zion.zionModeEnabled") private var zionModeEnabled: Bool = false
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

    private func route(_ event: NavigationEvent) {
        switch event {
        case .repositoryOpened:
            hasCompletedOnboarding = true
            shouldPresentOnboardingFromHelp = false
            selectedSection = model.nextSectionAfterRepositoryOpen ?? .code
            model.nextSectionAfterRepositoryOpen = nil
        case .requestSection(let section):
            if zenModeEnabled && section != .code {
                selectedSection = .code
                return
            }
            guard section == .code || model.repositoryURL != nil else {
                model.statusMessage = L10n("Abra um repositorio para acessar %@", L10n(section.title))
                return
            }
            selectedSection = section
        case .showOnboardingFromHelp:
            isHelpVisible = false
            selectedSection = .code
            shouldPresentOnboardingFromHelp = true
        case .navigateToGraph:
            selectedSection = zenModeEnabled ? .code : .graph
        case .navigateToCode:
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
                    .background(Color(NSColor.windowBackgroundColor))
                    .overlay {
                        if model.isRepositorySwitching {
                            ZionLoadingOverlay()
                                .transition(.opacity)
                        }
                    }
            }
            .navigationSplitViewStyle(.balanced)
            .frame(minWidth: 1360, minHeight: 840)
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
                    .keyboardShortcut("j", modifiers: [.command, .control])
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
        .animation(.easeInOut(duration: 0.15), value: model.isRepositorySwitching)
    }

    @ViewBuilder
    private var detailViewHost: some View {
        if launchPhase == .bootstrapping {
            Color.clear // Liquid background shows through during bootstrap
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
                    Button { model.fetch() } label: { Image(systemName: "arrow.down.circle") }
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
                        .help(L10n("zen.enter") + " (⌃⌘J)")
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
            Image(systemName: "exclamationmark.triangle.fill").font(.title3).foregroundStyle(DesignSystem.Colors.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n("Conflitos")).font(.headline)
                Text(L10n("Resolva os conflitos na sua IDE favorita.")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
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
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            if model.isBusy { ProgressView().controlSize(.small) }
            Text(model.statusMessage).lineLimit(1).font(.caption).foregroundStyle(.secondary)

            statusBarQuickNavigation

            Spacer()

            if model.repositoryURL != nil && !model.isRepositorySwitching {
                // Branch pill
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9))
                    Text(model.currentBranch)
                        .lineLimit(1)
                }
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(zionModeEnabled ? DesignSystem.ZionMode.neonMagenta.opacity(0.12) : DesignSystem.Colors.statusGreenBg)
                .foregroundStyle(zionModeEnabled ? DesignSystem.ZionMode.neonMagenta : DesignSystem.Colors.success)
                .clipShape(Capsule())

                // Ahead remote badge
                if model.aheadRemoteCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 9))
                        Text("\(model.aheadRemoteCount)")
                    }
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        zionModeEnabled
                            ? DesignSystem.ZionMode.neonGold.opacity(0.12)
                            : (model.behindRemoteCount > 0 ? DesignSystem.Colors.statusOrangeBg : DesignSystem.Colors.statusBlueBg)
                    )
                    .foregroundStyle(
                        zionModeEnabled
                            ? DesignSystem.ZionMode.neonGold
                            : (model.behindRemoteCount > 0 ? DesignSystem.Colors.warning : DesignSystem.Colors.info)
                    )
                    .clipShape(Capsule())
                }

                // Behind remote badge
                if model.behindRemoteCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 9))
                        Text("\(model.behindRemoteCount)")
                    }
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(zionModeEnabled ? DesignSystem.ZionMode.neonOrange.opacity(0.12) : DesignSystem.Colors.statusOrangeBg)
                    .foregroundStyle(zionModeEnabled ? DesignSystem.ZionMode.neonOrange : DesignSystem.Colors.warning)
                    .clipShape(Capsule())
                }

                // Uncommitted changes count
                if model.uncommittedCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 9))
                        Text("\(model.uncommittedCount)")
                    }
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(DesignSystem.Colors.statusBlueBg)
                    .foregroundStyle(DesignSystem.Colors.info)
                    .clipShape(Capsule())
                }
            }

            if let repositoryURL = model.repositoryURL {
                Text(repositoryURL.path).lineLimit(1).font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background {
            if zionModeEnabled {
                ZStack {
                    DesignSystem.ZionMode.neonBase
                    Rectangle().fill(.ultraThinMaterial)
                }
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
        .overlay(alignment: .top) {
            if zionModeEnabled {
                if model.isBusy {
                    NeonProgressLine(mode: .shimmer)
                        .transition(.opacity.animation(.easeOut(duration: 0.3)))
                } else {
                    DesignSystem.ZionMode.neonMagenta.opacity(0.25)
                        .frame(height: 1)
                        .transition(.opacity.animation(.easeIn(duration: 0.5)))
                }
            } else {
                Divider().opacity(0.45)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.isBusy)
    }

    private var statusBarQuickNavigation: some View {
        HStack(spacing: 4) {
            statusBarSectionButton(.code)
            statusBarSectionButton(.graph)
            statusBarSectionButton(.operations)

            Divider()
                .frame(height: 14)
                .padding(.horizontal, 2)

            statusBarSettingsButton
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(zionModeEnabled ? DesignSystem.ZionMode.neonMagenta.opacity(0.03) : DesignSystem.Colors.glassSubtle)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous)
                .stroke(zionModeEnabled ? DesignSystem.ZionMode.neonMagenta.opacity(0.12) : DesignSystem.Colors.glassBorderDark, lineWidth: 1)
        )
    }

    private func statusBarSectionButton(_ section: AppSection) -> some View {
        let isSelected = selectedSection == section
        let isDisabled = section != .code && model.repositoryURL == nil

        return Button {
            route(.requestSection(section))
        } label: {
            HStack(spacing: 4) {
                Image(systemName: section.icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(statusBarSectionLabel(section))
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous)
                    .fill(isSelected ? (zionModeEnabled ? DesignSystem.ZionMode.neonMagenta.opacity(0.12) : DesignSystem.Colors.selectionBackground) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous)
                    .stroke(isSelected ? (zionModeEnabled ? DesignSystem.ZionMode.neonMagenta.opacity(0.15) : DesignSystem.Colors.selectionBorder) : Color.clear, lineWidth: 1)
            )
            .overlay(alignment: .bottom) {
                if isSelected && zionModeEnabled {
                    DesignSystem.ZionMode.neonGradient
                        .frame(height: DesignSystem.ZionMode.neonLineHeight)
                        .padding(.horizontal, 4)
                        .clipShape(Capsule())
                        .opacity(0.7)
                        .shadow(color: DesignSystem.ZionMode.neonMagenta.opacity(0.2),
                                radius: 1, y: 1)
                        .transition(.opacity)
                        .animation(DesignSystem.Motion.detail, value: isSelected)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .help(statusBarSectionLabel(section))
        .accessibilityLabel(statusBarSectionLabel(section))
    }

    private var statusBarSettingsButton: some View {
        SettingsLink {
            HStack(spacing: 4) {
                Image(systemName: "gearshape")
                    .font(.system(size: 9, weight: .semibold))
                Text(L10n("status.nav.settings"))
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n("settings.open.hint"))
        .accessibilityLabel(L10n("status.nav.settings"))
    }

    private func statusBarSectionLabel(_ section: AppSection) -> String {
        L10n(section.title)
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

        Button(L10n("Merge into Current")) {
            performGitAction(title: L10n("Merge into Current"), message: L10n("Fazer merge da branch informada na atual?"), destructive: false) {
                model.mergeBranch(named: branch) 
            }
        }
        Button(L10n("Rebase Current onto This")) {
            performGitAction(title: L10n("Rebase Current onto This"), message: L10n("Rebasear a branch atual no target informado?"), destructive: true) {
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

        if model.isAIConfigured {
            Divider()
            Button {
                model.summarizeBranch(branch)
            } label: {
                if model.isGeneratingAIMessage {
                    Label(L10n("Resumindo..."), systemImage: "sparkles")
                } else if let summary = model.branchSummaries[branch] {
                    Label(summary, systemImage: "sparkles")
                } else {
                    Label(L10n("Resumir com IA"), systemImage: "sparkles")
                }
            }
            .disabled(model.isGeneratingAIMessage)
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
    @Environment(\.zionModeEnabled) private var zionMode
    @State private var phase: Bool = false

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                if zionMode {
                    // Zion Mode: deep purple base with neon orbs
                    DesignSystem.ZionMode.neonBaseDark.ignoresSafeArea()
                    Circle()
                        .fill(DesignSystem.ZionMode.neonMagenta.opacity(phase ? 0.20 : 0.16))
                        .frame(width: 600).blur(radius: 100)
                        .offset(x: phase ? -310 : -370, y: phase ? -200 : -240)
                    Circle()
                        .fill(DesignSystem.ZionMode.neonCyan.opacity(phase ? 0.15 : 0.11))
                        .frame(width: 500).blur(radius: 90)
                        .offset(x: phase ? 310 : 260, y: phase ? -260 : -300)
                    Circle()
                        .fill(DesignSystem.ZionMode.neonGold.opacity(phase ? 0.08 : 0.05))
                        .frame(width: 350).blur(radius: 70)
                        .offset(x: phase ? 280 : 320, y: phase ? 220 : 260)
                } else {
                    Color(red: 0.05, green: 0.02, blue: 0.10).ignoresSafeArea()
                    Circle()
                        .fill(DesignSystem.Colors.brandPrimary.opacity(phase ? 0.17 : 0.14))
                        .frame(width: 520).blur(radius: 80)
                        .offset(x: phase ? -310 : -370, y: phase ? -200 : -240)
                    Circle()
                        .fill(DesignSystem.Colors.brandInk.opacity(0.12))
                        .frame(width: 420).blur(radius: 70)
                        .offset(x: phase ? 310 : 260, y: phase ? -260 : -300)
                }
            } else {
                Color(red: 0.96, green: 0.94, blue: 1.00).ignoresSafeArea()
                Circle()
                    .fill(DesignSystem.Colors.brandPrimary.opacity(phase ? 0.12 : 0.09))
                    .frame(width: 520).blur(radius: 80)
                    .offset(x: phase ? -310 : -370, y: phase ? -200 : -240)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                phase.toggle()
            }
        }
    }
}
