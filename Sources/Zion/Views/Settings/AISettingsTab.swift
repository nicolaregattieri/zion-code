import SwiftUI

struct AISettingsTab: View {
    @AppStorage(UserDefaultsKeys.AI.provider) private var aiProviderRaw: String = AIProvider.none.rawValue
    @AppStorage(UserDefaultsKeys.AI.mode) private var aiModeRaw: String = AIMode.efficient.rawValue
    @AppStorage(UserDefaultsKeys.AI.commitMessageStyle) private var commitStyleRaw: String = CommitMessageStyle.compact.rawValue
    @AppStorage(UserDefaultsKeys.AI.preCommitReview) private var preCommitReviewEnabled: Bool = false
    @AppStorage(UserDefaultsKeys.AI.transferSupportHints) private var aiTransferSupportHints: Bool = true
    // Both flags default to true (opt-out). Power users who want stricter
    // posture flip them off here. Backing UserDefaults keys are read elsewhere
    // (ProviderOrchestrator + ZionHarness) using the same default = true so
    // a brand-new install behaves the same whether the user visits this tab
    // or not.
    @AppStorage("chat.routing.subscriptionFailover") private var subscriptionFailover: Bool = true
    // `chat.allowEdits` and `chat.globalSystemPrompt` were previously surfaced
    // here. They live in `ZionTalksSettingsTab` now — both are chat-scoped
    // (the keys use the `chat.` namespace) and surfacing them next to
    // cross-cutting AI provider settings created the wrong mental model.
    @AppStorage(UserDefaultsKeys.RepoMemory.activeRepoName) private var repoMemoryRepoName: String = ""
    @AppStorage(UserDefaultsKeys.RepoMemory.lastRefresh) private var repoMemoryLastRefresh: Double = 0
    @AppStorage(UserDefaultsKeys.RepoMemory.ready) private var repoMemoryReady: Bool = false

    @State private var aiKeyInput: String = ""
    @State private var editingProvider: AIProvider?
    @State private var connectionRefreshID: Int = 0
    @State private var localConfig: LocalLLMConfig = LocalLLMConfig()
    @State private var claudeStatus: CLIToolStatus?
    @State private var codexStatus: CLIToolStatus?
    @State private var cliDiscovery = CLIDiscoveryService()
    @State private var repoMemoryActionFeedback: String? = nil

    // Cached results — recomputed off-main via `refreshConnections()`. Previously
    // these were computed-properties that ran `AIClient.loadAPIKey` (sync
    // `SecItemCopyMatching`) for EVERY provider on EVERY body recompute. With
    // multiple @AppStorage observers in scope, SwiftUI re-runs body many times
    // per second; the resulting Keychain spam saturated the main thread and
    // hung the AI Settings tab for tens of seconds (hang reports show
    // SwiftUI runTransaction → DynamicBody.updateValue → GroupedSection
    // looping while waiting on Keychain).
    @State private var providerConnections: [AIProviderConnectionInfo] = []
    @State private var isDefaultProviderConnected: Bool = false

    private var defaultProvider: AIProvider {
        AIProvider(rawValue: aiProviderRaw) ?? .none
    }

    private var mode: AIMode {
        AIMode(rawValue: aiModeRaw) ?? .efficient
    }

    private func refreshConnections() async {
        let provider = defaultProvider
        let (infos, connected) = await Task.detached(priority: .userInitiated) {
            let infos = AIProviderSupport.connectionInfo().filter {
                $0.provider != .local && $0.provider != .claudeCLI && $0.provider != .codexCLI
            }
            let connected = AIProviderSupport.isConnected(provider: provider)
            return (infos, connected)
        }.value
        providerConnections = infos
        isDefaultProviderConnected = connected
    }

    private var repoMemoryStatusText: String {
        guard !repoMemoryRepoName.isEmpty else {
            return L10n("settings.ai.repoMemory.status.closed")
        }

        let refreshText: String
        if repoMemoryLastRefresh > 0 {
            let date = Date(timeIntervalSince1970: repoMemoryLastRefresh)
            refreshText = DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
        } else {
            refreshText = L10n("settings.ai.repoMemory.status.notBuilt")
        }

        if repoMemoryReady {
            return L10n("settings.ai.repoMemory.status.readyDetail", repoMemoryRepoName, refreshText)
        }

        return L10n("settings.ai.repoMemory.status.pendingDetail", repoMemoryRepoName)
    }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.iconLabelGap) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(DesignSystem.Colors.ai)
                        .padding(.top, 2)
                    Text(L10n("settings.ai.tab.intro"))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section(L10n("settings.ai.defaultProvider")) {
                Picker(L10n("settings.ai.defaultProvider"), selection: $aiProviderRaw) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.label).tag(provider.rawValue)
                    }
                }
                .onChange(of: aiProviderRaw) { _, _ in
                    cancelEditing()
                }

                Text(L10n("settings.ai.defaultProvider.hint"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)

                if defaultProvider != .none && defaultProvider != .local && defaultProvider != .claudeCLI && defaultProvider != .codexCLI && !isDefaultProviderConnected {
                    Label(L10n("settings.ai.defaultProvider.missingKey"), systemImage: "exclamationmark.triangle.fill")
                        .font(DesignSystem.Typography.labelMedium)
                        .foregroundStyle(DesignSystem.Colors.warning)

                    Text(L10n("settings.ai.defaultProvider.recovery"))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                }
            }

            if defaultProvider == .local {
                LocalLLMSettingsSection(config: $localConfig)
            } else {
                Section(L10n("settings.ai.connectedProviders")) {
                    ForEach(providerConnections, id: \.provider) { info in
                        providerRow(info)
                    }

                    Text(L10n("settings.ai.connectedProviders.hint"))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                }
            }

            Section(L10n("settings.ai.cli.subscription.title")) {
                cliToolRow(tool: .claude, status: claudeStatus)
                cliToolRow(tool: .codex, status: codexStatus)

            }
            .task {
                await refreshCLIStatus()
            }

            Section(L10n("settings.ai.routing.title")) {
                Toggle(L10n("settings.ai.safety.subscriptionFailover"),
                       isOn: $subscriptionFailover)
                Text(L10n("settings.ai.safety.subscriptionFailover.hint"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
            }

            ProjectGuidanceSettingsSection()

            if defaultProvider != .none {
                Section(L10n("settings.ai.mode")) {
                    Picker(L10n("settings.ai.mode"), selection: $aiModeRaw) {
                        ForEach(AIMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(mode.hint)
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                }

                Section(L10n("settings.ai.commitStyle")) {
                    Picker(L10n("settings.ai.commitStyle"), selection: $commitStyleRaw) {
                        ForEach(CommitMessageStyle.allCases) { style in
                            Text(style.label).tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(commitStyleRaw == CommitMessageStyle.compact.rawValue
                        ? L10n("commit.style.compact.hint")
                        : L10n("commit.style.detailed.hint"))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                }

                Section(L10n("settings.ai.preCommitReview")) {
                    Toggle(L10n("settings.ai.preCommitReview.toggle"), isOn: $preCommitReviewEnabled)
                    Text(L10n("settings.ai.preCommitReview.hint"))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                }

                Section(L10n("settings.ai.mapping")) {
                    ForEach(AIModelCatalogService.mappingRows(for: defaultProvider, mode: mode), id: \.lane) { row in
                        HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.iconLabelGap) {
                            Image(systemName: laneIcon(row.lane))
                                .foregroundStyle(laneColor(row.lane))
                                .frame(width: 16)
                            Text(row.lane.label)
                                .font(DesignSystem.Typography.labelBold)
                            Spacer()
                            Text(row.modelID)
                                .font(DesignSystem.Typography.monoLabel)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Text(L10n("settings.ai.mapping.hint"))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                }

                Section(L10n("settings.ai.repoMemory")) {
                    Text(repoMemoryStatusText)
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button(L10n("settings.ai.repoMemory.refresh")) {
                            NotificationCenter.default.post(name: .refreshRepoMemory, object: nil)
                            flashRepoMemoryFeedback(L10n("settings.ai.repoMemory.refresh.queued"))
                        }
                        .disabled(repoMemoryRepoName.isEmpty)

                        Spacer()

                        Button(L10n("settings.ai.repoMemory.clear")) {
                            NotificationCenter.default.post(name: .clearRepoMemory, object: nil)
                            flashRepoMemoryFeedback(L10n("settings.ai.repoMemory.clear.queued"))
                        }
                        .disabled(repoMemoryRepoName.isEmpty)
                    }
                    // Inline feedback strip — buttons used to post a
                    // Notification with no acknowledgement, so users could
                    // not tell whether the click did anything.
                    if let feedback = repoMemoryActionFeedback {
                        HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(DesignSystem.Colors.success)
                            Text(feedback)
                                .font(DesignSystem.Typography.label)
                                .foregroundStyle(.secondary)
                        }
                        .transition(.opacity)
                    }
                }
            }

            Section(L10n("settings.ai.transferSupport")) {
                Toggle(L10n("settings.ai.transferSupport.toggle"), isOn: $aiTransferSupportHints)
                Text(L10n("settings.ai.transferSupport.hint"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.actionPrimary))
        .tint(DesignSystem.Colors.actionPrimary)
        .onAppear {
            cancelEditing()
            localConfig = AIClient.loadLocalConfig() ?? LocalLLMConfig()
        }
        .onChange(of: localConfig) { _, newValue in
            AIClient.saveLocalConfig(newValue)
        }
        .task {
            await refreshConnections()
        }
        .onChange(of: connectionRefreshID) { _, _ in
            Task { await refreshConnections() }
        }
        .onChange(of: aiProviderRaw) { _, _ in
            Task { await refreshConnections() }
        }
    }

    // MARK: - CLI Status

    private func refreshCLIStatus() async {
        // Use cache on initial tab open (TTL = 5min). The Refresh button per row
        // calls `status(for:refresh:true)` explicitly. Forcing refresh on every
        // `.task` invocation re-spawned `which claude` + `claude --version` (and
        // codex equivalents) on every tab visit — each subprocess can take
        // seconds when shell init is slow, leaving the row spinner stuck even
        // though work runs off-main now.
        async let claudeResult = cliDiscovery.status(for: .claude, refresh: false)
        async let codexResult = cliDiscovery.status(for: .codex, refresh: false)
        let (c, d) = await (claudeResult, codexResult)
        claudeStatus = c
        codexStatus = d
    }

    @ViewBuilder
    private func cliToolRow(tool: CLITool, status: CLIToolStatus?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                Image(systemName: tool == .claude
                      ? "a.circle.fill"
                      : "chevron.left.forwardslash.chevron.right")
                    .foregroundStyle(DesignSystem.Colors.ai)
                Text(tool == .claude
                     ? L10n("settings.ai.provider.claudeCLI")
                     : L10n("settings.ai.provider.codexCLI"))
                    .font(DesignSystem.Typography.bodySemibold)

                Spacer()

                if let status {
                    cliStatusPill(status: status)
                } else {
                    ProgressView()
                        .scaleEffect(0.7)
                }

                Button(L10n("settings.ai.cli.refresh")) {
                    Task {
                        let fresh = await cliDiscovery.status(for: tool, refresh: true)
                        if tool == .claude {
                            claudeStatus = fresh
                        } else {
                            codexStatus = fresh
                        }
                    }
                }
                .buttonStyle(.bordered)
                .font(DesignSystem.Typography.label)
            }

            if let status {
                if status.installed {
                    if let version = status.version {
                        Text(L10n("settings.ai.cli.installed", version))
                            .font(DesignSystem.Typography.label)
                            .foregroundStyle(.secondary)
                    }
                    if status.isAuthenticated != true {
                        let hintKey = tool == .claude
                            ? "settings.ai.cli.notAuthenticated.claude.hint"
                            : "settings.ai.cli.notAuthenticated.codex.hint"
                        Text(L10n(hintKey))
                            .font(DesignSystem.Typography.label)
                            .foregroundStyle(DesignSystem.Colors.warning)
                    }
                } else {
                    let hintKey = tool == .claude
                        ? "settings.ai.cli.notInstalled.claude.hint"
                        : "settings.ai.cli.notInstalled.codex.hint"
                    HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                        Text(L10n(hintKey))
                            .font(DesignSystem.Typography.label)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(L10n(hintKey), forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(DesignSystem.Typography.label)
                        }
                        .buttonStyle(.borderless)
                        .help(L10n("chat.code.copy"))
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func cliStatusPill(status: CLIToolStatus) -> some View {
        let (color, label): (Color, String) = {
            if status.installed && status.isAuthenticated == true {
                return (DesignSystem.Colors.success, L10n("settings.ai.provider.status.connected"))
            } else if status.installed {
                return (DesignSystem.Colors.warning, L10n("settings.ai.provider.status.notConnected"))
            } else {
                return (DesignSystem.Colors.error, L10n("settings.ai.cli.notInstalled"))
            }
        }()
        Text(label)
            .font(DesignSystem.Typography.metaSemibold)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    // MARK: - Provider Rows

    @ViewBuilder
    private func providerRow(_ info: AIProviderConnectionInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.iconLabelGap) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                        Text(info.provider.label)
                            .font(DesignSystem.Typography.bodySemibold)

                        if defaultProvider == info.provider {
                            Text(L10n("settings.ai.provider.defaultBadge"))
                                .font(DesignSystem.Typography.metaSemibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(DesignSystem.Colors.selectionBackground)
                                .clipShape(Capsule())
                        }
                    }

                    Text(info.isConnected ? L10n("settings.ai.provider.status.connected") : L10n("settings.ai.provider.status.notConnected"))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(info.isConnected ? DesignSystem.Colors.success : .secondary)
                }

                Spacer()

                if let dashboardURL = info.dashboardURL {
                    Link(destination: dashboardURL) {
                        Label(L10n("settings.ai.provider.openDashboard"), systemImage: "arrow.up.right.square")
                            .font(DesignSystem.Typography.label)
                    }
                }
            }

            if info.supportsWhisper {
                Text(L10n("settings.ai.provider.openaiWhisperHint"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                Button(editingProvider == info.provider
                    ? L10n("settings.ai.provider.cancelEdit")
                    : (info.isConnected ? L10n("settings.ai.provider.editKey") : L10n("settings.ai.provider.addKey"))) {
                    if editingProvider == info.provider {
                        cancelEditing()
                    } else {
                        beginEditing(info.provider)
                    }
                }
                .buttonStyle(.bordered)

                if info.isConnected {
                    Button(L10n("settings.ai.provider.removeKey")) {
                        removeKey(for: info.provider)
                    }
                    .buttonStyle(.bordered)
                    .tint(DesignSystem.Colors.destructive)
                }
            }

            if editingProvider == info.provider {
                VStack(alignment: .leading, spacing: 8) {
                    SecureField(L10n("settings.ai.provider.keyPlaceholder"), text: $aiKeyInput)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                                .fill(DesignSystem.Colors.glassHover)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                                .stroke(DesignSystem.Colors.glassStroke, lineWidth: 1)
                        )
                        .onSubmit { saveKey(for: info.provider) }

                    HStack {
                        Spacer()
                        Button(L10n("settings.ai.provider.saveKey")) {
                            saveKey(for: info.provider)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.actionPrimary)
                        .disabled(aiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Glyph mapping for the lane → model mapping rows. Distinguishes
    /// cheapSummary (leaf) / general (sparkles) / reasoning (brain) /
    /// review (eyes / pen) / code (chevrons) so the list is scannable
    /// instead of a wall of identical bold labels.
    private func laneIcon(_ lane: AITaskLane) -> String {
        switch lane {
        case .cheapSummary:  return "leaf"
        case .general:       return "sparkles"
        case .reasoning:     return "brain"
        case .review:        return "checkmark.shield"
        case .transcription: return "waveform"
        }
    }

    private func laneColor(_ lane: AITaskLane) -> Color {
        switch lane {
        case .cheapSummary:  return DesignSystem.Colors.success
        case .general:       return DesignSystem.Colors.ai
        case .reasoning:     return DesignSystem.Colors.warning
        case .review:        return DesignSystem.Colors.info
        case .transcription: return DesignSystem.Colors.textSecondary
        }
    }

    /// Shows a green checkmark + message under the repo-memory buttons for
    /// 2.5 seconds so the user gets visible acknowledgement that the
    /// Notification was dispatched.
    private func flashRepoMemoryFeedback(_ message: String) {
        repoMemoryActionFeedback = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if repoMemoryActionFeedback == message {
                repoMemoryActionFeedback = nil
            }
        }
    }

    private func beginEditing(_ provider: AIProvider) {
        editingProvider = provider
        aiKeyInput = AIClient.loadAPIKey(for: provider) ?? ""
    }

    private func cancelEditing() {
        editingProvider = nil
        aiKeyInput = ""
    }

    private func saveKey(for provider: AIProvider) {
        let trimmedKey = aiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }
        AIClient.saveAPIKey(trimmedKey, for: provider)
        connectionRefreshID += 1
        cancelEditing()
    }

    private func removeKey(for provider: AIProvider) {
        AIClient.deleteAPIKey(for: provider)
        connectionRefreshID += 1
        if editingProvider == provider {
            cancelEditing()
        }
    }
}
