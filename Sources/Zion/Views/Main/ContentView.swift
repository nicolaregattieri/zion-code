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
    @EnvironmentObject var shortcutRegistry: ShortcutRegistry
    @State var isShortcutsVisible: Bool = false
    @State var isHelpVisible: Bool = false
    @State private var shouldPresentOnboardingFromHelp: Bool = false
    @State private var isFeatureTourVisible: Bool = false
    @State private var currentFeatureTourIndex: Int = 0
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .all
    @State private var shellWidth: CGFloat = DesignSystem.Layout.windowMinWidth
    @State private var zenLayoutActive = false
    @State private var zenTerminalFullscreen = false
    @State private var zenTransitioning = false
    @State private var zenTransitionMessage = ""
    @State private var preZenSplitVisibility: NavigationSplitViewVisibility?
    @State private var preCompactSplitVisibility: NavigationSplitViewVisibility?
    @State private var isCompactSidebarCollapsed = false
    @State private var pendingNavigationAfterZenExit: AppSection?
    @State private var isConflictResolverPromptVisible: Bool = false
    @State private var hasShownConflictResolverPromptForCurrentConflictState: Bool = false

    @AppStorage(UserDefaultsKeys.General.confirmationMode) var confirmationModeRaw: String = ConfirmationMode.destructiveOnly.rawValue
    @AppStorage(UserDefaultsKeys.General.uiLanguage) private var uiLanguageRaw: String = AppLanguage.system.rawValue
    @AppStorage(UserDefaultsKeys.General.appearance) private var appearanceRaw: String = AppAppearance.system.rawValue
    @AppStorage(UserDefaultsKeys.General.hasCompletedOnboarding) private var hasCompletedOnboarding: Bool = false
    @AppStorage(UserDefaultsKeys.General.hasCompletedFeatureTour) private var hasCompletedFeatureTour: Bool = false
    @AppStorage(UserDefaultsKeys.General.hasOpenedRepositoryOnce) private var hasOpenedRepositoryOnce: Bool = false
    @AppStorage(UserDefaultsKeys.General.zenModeEnabled) var zenModeEnabled: Bool = false
    @AppStorage(UserDefaultsKeys.General.zionModeEnabled) var zionModeEnabled: Bool = false
    @AppStorage(UserDefaultsKeys.General.preZionModeTheme) private var preZionModeTheme: String = ""

    private var uiLanguage: AppLanguage { AppLanguage(rawValue: uiLanguageRaw) ?? .system }
    private var appearance: AppAppearance { AppAppearance(rawValue: appearanceRaw) ?? .system }
    private let featureTourSteps = ContextualFeatureTourStep.allCases
    var statusBarClearance: CGFloat { zenLayoutActive ? 0 : DesignSystem.Spacing.statusBarClearance }
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
        if model.repositoryURL == nil {
            return .welcome
        }
        return .workspace
    }

    private let logger = DiagnosticLogger.shared
    var shellLayoutProfile: AppShellLayoutProfile {
        AppShellLayoutProfile(width: shellWidth)
    }
    var isPrimarySidebarVisible: Bool {
        splitViewVisibility != .detailOnly
    }

    func route(_ event: NavigationEvent) {
        switch event {
        case .repositoryOpened:
            hasCompletedOnboarding = true
            shouldPresentOnboardingFromHelp = false
            model.isBridgeVisible = false
            selectedSection = model.nextSectionAfterRepositoryOpen ?? .code
            model.nextSectionAfterRepositoryOpen = nil
        case .requestSection(let section):
            if zenModeEnabled {
                if section != .code {
                    pendingNavigationAfterZenExit = section
                }
                toggleZenMode()
                return
            }
            guard model.canAccess(section) else {
                model.statusMessage = L10n("Abra uma pasta para acessar %@", L10n(section.title))
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
            if zenModeEnabled {
                pendingNavigationAfterZenExit = .graph
                toggleZenMode()
            } else {
                selectedSection = .graph
            }
        case .navigateToCode:
            model.isBridgeVisible = false
            if zenModeEnabled {
                toggleZenMode()
            }
            selectedSection = .code
        }
    }

    var body: some View {
        configuredRootView
    }

    private var configuredRootView: some View {
        applyFeatureTourOverlay(
            to: applyInteractionModifiers(
                to: applyPresentationModifiers(
                    to: rootEnvironmentView
                )
            )
        )
    }

    private var rootEnvironmentView: some View {
        rootShell
        .id(uiLanguageRaw)
        .preferredColorScheme(zionModeEnabled ? .dark : appearance.colorScheme)
        .environment(\.locale, uiLanguage.locale)
        .environment(\.zionModeEnabled, zionModeEnabled)
        .onAppear {
            RepositoryViewModel.activeReference.value = model
            logger.log(.info, "Boot: starting", source: "ContentView")
            model.clipboardMonitor.start()
            model.restoreEditorSettings()
            if !hasOpenedRepositoryOnce,
               FeatureTourLaunchPolicy.inferredExistingRepositoryHistory(
                from: UserDefaults.standard.data(forKey: UserDefaultsKeys.General.recentRepositories)
               ) {
                hasOpenedRepositoryOnce = true
            }
            let result = model.restoreLastRepository()
            switch result {
            case .opened(let url):
                hasCompletedOnboarding = true
                hasOpenedRepositoryOnce = true
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
            zenLayoutActive = zenModeEnabled
            zenTerminalFullscreen = zenModeEnabled
            splitViewVisibility = zenModeEnabled ? .detailOnly : .all
            applyResponsiveShellLayout(for: shellWidth)
            if zenModeEnabled {
                selectedSection = .code
                model.enterZenMode()
            }
        }
        .onDisappear {
            if RepositoryViewModel.activeReference.value === model {
                RepositoryViewModel.activeReference.value = nil
            }
            model.clipboardMonitor.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            model.syncSettingsFromDefaults()
        }
        .onChange(of: zenModeEnabled) { _, _ in
            // All zen mode logic handled by toggleZenMode() which shows overlay first
        }
        .onChange(of: model.repositoryURL) { _, url in
            if url != nil {
                let shouldAutoStartFeatureTour = FeatureTourLaunchPolicy.shouldAutoStartFirstRepositoryTour(
                    hasOpenedRepositoryOnce: hasOpenedRepositoryOnce,
                    hasCompletedFeatureTour: hasCompletedFeatureTour
                )
                route(.repositoryOpened)
                hasOpenedRepositoryOnce = true
                if shouldAutoStartFeatureTour {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        startFeatureTour()
                    }
                }
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


    }

    private func applyInteractionModifiers<Content: View>(to view: Content) -> some View {
        view
        .onReceive(NotificationCenter.default.publisher(for: .showKeyboardShortcuts)) { _ in
            isShortcutsVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showHelp)) { _ in
            isHelpVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showOnboarding)) { _ in
            route(.showOnboardingFromHelp)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showFeatureTour)) { _ in
            if model.hasGitWorkspace {
                startFeatureTour()
            } else {
                route(.showOnboardingFromHelp)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleZenMode)) { _ in
            toggleZenMode()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleZionMode)) { _ in
            zionModeEnabled.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFilesFromFinder)) { notification in
            guard let urls = notification.userInfo?["urls"] as? [URL] else { return }
            model.openExternalFiles(urls)
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshRepoMemory)) { _ in
            Task { await model.refreshRepoMemory(force: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clearRepoMemory)) { _ in
            Task { await model.clearRepoMemory() }
        }
        .onChange(of: zionModeEnabled) { oldValue, enabled in
            if enabled {
                preZionModeTheme = UserDefaults.standard.string(forKey: UserDefaultsKeys.Editor.theme) ?? EditorTheme.dracula.rawValue
                UserDefaults.standard.set(EditorTheme.synthwave.rawValue, forKey: UserDefaultsKeys.Editor.theme)
            } else if oldValue {
                // Only restore if explicitly toggled off (not auto-disabled by theme change)
                let currentTheme = UserDefaults.standard.string(forKey: UserDefaultsKeys.Editor.theme) ?? ""
                if currentTheme == EditorTheme.synthwave.rawValue {
                    let restore = preZionModeTheme.isEmpty ? EditorTheme.dracula.rawValue : preZionModeTheme
                    UserDefaults.standard.set(restore, forKey: UserDefaultsKeys.Editor.theme)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            // Auto-disable Zion Mode if user manually picks a different theme
            if zionModeEnabled {
                let currentTheme = UserDefaults.standard.string(forKey: UserDefaultsKeys.Editor.theme) ?? ""
                if currentTheme != EditorTheme.synthwave.rawValue {
                    zionModeEnabled = false
                }
            }
        }
        .animation(DesignSystem.Motion.detail, value: model.isRepositorySwitchBlocking)
    }

    private func applyFeatureTourOverlay<Content: View>(to view: Content) -> some View {
        view.overlayPreferenceValue(FeatureTourFramePreferenceKey.self) { frames in
            if isFeatureTourVisible {
                ContextualFeatureTourOverlay(
                    steps: featureTourSteps,
                    currentIndex: currentFeatureTourIndex,
                    anchorFrames: frames,
                    onBack: moveFeatureTourBackward,
                    onNext: advanceFeatureTour,
                    onSkip: completeFeatureTour
                )
            }
        }
    }

    private func applyPresentationModifiers<Content: View>(to view: Content) -> some View {
        view
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
        .sheet(item: $model.divergenceResolution) { context in
            DivergenceResolutionSheet(context: context) { resolution in
                model.resolveDivergence(resolution, context: context)
            }
        }
    }

    private var rootShell: some View {
        ZStack {
            LiquidBackgroundView().ignoresSafeArea()
            navigationShell
            if zenTransitioning {
                ZionLoadingOverlay(message: zenTransitionMessage)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .coordinateSpace(name: "featureTour")
        .background(shellWidthReader)
    }

    private var navigationShell: some View {
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
            detailContainer
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
            if !zenLayoutActive {
                mainToolbar
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !zenLayoutActive {
                statusBar
            }
        }
        .background {
            keyboardShortcutBridge
        }
    }

    private var shellWidthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    updateShellWidth(proxy.size.width)
                }
                .onChange(of: proxy.size) { _, size in
                    updateShellWidth(size.width)
                }
        }
    }

    private var detailContainer: some View {
        detailViewHost
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(!model.isRepositorySwitchBlocking)
            .padding(.bottom, statusBarClearance)
            .background(DesignSystem.Colors.background)
            .overlay {
                if model.isRepositorySwitchBlocking {
                    ZionLoadingOverlay()
                        .transition(.opacity)
                }
            }
    }

    @ViewBuilder
    private var detailViewHost: some View {
        if launchPhase == .bootstrapping {
            Color.clear // Liquid background shows through during bootstrap
        } else if model.isBridgeVisible, model.hasGitWorkspace {
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
        // All sections are kept in the ZStack at stable structural positions to avoid
        // destroying/creating heavy views (terminals, graph, operations) on section switches.
        ZStack {
            CodeScreen(model: model, onOpenFolder: { openRepositoryPanel() }, isZenMode: zenLayoutActive, zenTerminalFullscreen: zenTerminalFullscreen, isVisible: selectedSection == .code)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(selectedSection == .code ? 1 : 0)
                .allowsHitTesting(selectedSection == .code)

            if model.hasGitWorkspace {
                nonCodeSharedBanners
                    .opacity(selectedSection != .code ? 1 : 0)
                    .allowsHitTesting(selectedSection != .code)

                GraphScreen(
                    model: model,
                    commitSearchQuery: $commitSearchQuery,
                    performGitAction: { t, m, d, a in performGitAction(title: t, message: m, destructive: d, action: a) },
                    commitContextMenu: { commit in AnyView(commitContextMenu(for: commit)) },
                    branchContextMenu: { branch in AnyView(branchContextMenu(for: branch)) },
                    tagContextMenu: { tag in AnyView(tagContextMenu(for: tag)) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(selectedSection == .graph ? 1 : 0)
                .allowsHitTesting(selectedSection == .graph)

                OperationsScreen(
                    model: model,
                    performGitAction: { t, m, d, a in performGitAction(title: t, message: m, destructive: d, action: a) },
                    branchContextMenu: { branch in AnyView(branchContextMenu(for: branch)) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(selectedSection == .operations ? 1 : 0)
                .allowsHitTesting(selectedSection == .operations)
            } else if selectedSection != .code {
                WelcomeScreen(model: model, onOpen: { openRepositoryPanel() }, onInit: { initRepositoryPanel() })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(DesignSystem.Motion.panel, value: selectedSection)
    }

    func updateShellWidth(_ width: CGFloat) {
        guard width.isFinite, width > 0 else { return }
        let roundedWidth = width.rounded(.toNearestOrAwayFromZero)
        guard roundedWidth != shellWidth else { return }
        shellWidth = roundedWidth
        applyResponsiveShellLayout(for: roundedWidth)
    }

    func applyResponsiveShellLayout(for width: CGFloat) {
        guard !zenLayoutActive else { return }

        let profile = AppShellLayoutProfile(width: width)
        if profile.prefersCollapsedPrimarySidebar {
            guard !isCompactSidebarCollapsed else { return }
            preCompactSplitVisibility = splitViewVisibility
            splitViewVisibility = .detailOnly
            isCompactSidebarCollapsed = true
            return
        }

        guard isCompactSidebarCollapsed else { return }
        let restoreVisibility = preCompactSplitVisibility ?? .all
        splitViewVisibility = restoreVisibility
        preCompactSplitVisibility = nil
        isCompactSidebarCollapsed = false
    }

    @ViewBuilder
    private var nonCodeSharedBanners: some View {
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

            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
    }

    func openRepositoryPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        if panel.runModal() == .OK, let selectedURL = panel.url { model.openRepository(selectedURL) }
    }

    func togglePrimarySidebar() {
        splitViewVisibility = splitViewVisibility == .detailOnly ? .all : .detailOnly
        if !shellLayoutProfile.prefersCollapsedPrimarySidebar {
            preCompactSplitVisibility = splitViewVisibility
            isCompactSidebarCollapsed = false
        }
    }

    func toggleZenMode() {
        guard !zenTransitioning else { return }

        // Step 1: Show overlay FIRST — nothing else changes yet
        zenTransitionMessage = zenModeEnabled ? L10n("zen.exiting") : L10n("zen.entering")
        withAnimation(DesignSystem.Motion.panel) {
            zenTransitioning = true
        }

        // Step 2: After overlay fully covers screen, snap ALL state at once
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.Timing.zenModeRestoreDelay) {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                let entering = !zenModeEnabled
                if entering {
                    preZenSplitVisibility = splitViewVisibility
                    zenModeEnabled = true
                    selectedSection = .code
                    zenLayoutActive = true
                    zenTerminalFullscreen = true
                    splitViewVisibility = .detailOnly
                    model.enterZenMode()
                } else {
                    let restoreVisibility = preZenSplitVisibility ?? .all
                    preZenSplitVisibility = nil
                    zenModeEnabled = false
                    zenLayoutActive = false
                    zenTerminalFullscreen = false
                    splitViewVisibility = restoreVisibility
                    applyResponsiveShellLayout(for: shellWidth)
                    model.exitZenMode()
                    if let pending = pendingNavigationAfterZenExit {
                        pendingNavigationAfterZenExit = nil
                        selectedSection = pending
                    }
                }
            }

            // Step 3: After layout settles, remove overlay
            DispatchQueue.main.asyncAfter(deadline: .now() + Constants.Timing.zenModeStepDelay) {
                withAnimation(DesignSystem.Motion.panel) {
                    zenTransitioning = false
                }
            }
        }
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

    private func startFeatureTour() {
        guard model.hasGitWorkspace else { return }

        if zenModeEnabled {
            zenModeEnabled = false
            zenLayoutActive = false
            zenTerminalFullscreen = false
            splitViewVisibility = .all
            applyResponsiveShellLayout(for: shellWidth)
        }

        currentFeatureTourIndex = 0
        isFeatureTourVisible = true
    }

    private func moveFeatureTourBackward() {
        guard currentFeatureTourIndex > 0 else { return }
        withAnimation(DesignSystem.Motion.panel) {
            currentFeatureTourIndex -= 1
        }
    }

    private func advanceFeatureTour() {
        let nextIndex = currentFeatureTourIndex + 1
        guard nextIndex < featureTourSteps.count else {
            completeFeatureTour()
            return
        }

        withAnimation(DesignSystem.Motion.panel) {
            currentFeatureTourIndex = nextIndex
        }
    }

    private func completeFeatureTour() {
        hasCompletedFeatureTour = true
        withAnimation(DesignSystem.Motion.detail) {
            isFeatureTourVisible = false
        }
    }
}
