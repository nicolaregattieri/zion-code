import SwiftUI

struct AISettingsTab: View {
    @AppStorage(UserDefaultsKeys.AI.provider) private var aiProviderRaw: String = AIProvider.none.rawValue
    @AppStorage(UserDefaultsKeys.AI.mode) private var aiModeRaw: String = AIMode.efficient.rawValue
    @AppStorage(UserDefaultsKeys.AI.commitMessageStyle) private var commitStyleRaw: String = CommitMessageStyle.compact.rawValue
    @AppStorage(UserDefaultsKeys.AI.preCommitReview) private var preCommitReviewEnabled: Bool = false
    @AppStorage(UserDefaultsKeys.AI.transferSupportHints) private var aiTransferSupportHints: Bool = true
    @AppStorage("chat.toolsEnabled") private var chatToolsEnabled: Bool = true
    @AppStorage("chat.allowEdits") private var chatAllowEdits: Bool = false
    @AppStorage("chat.autoInject") private var chatAutoInject: Bool = true
    @AppStorage(UserDefaultsKeys.RepoMemory.activeRepoName) private var repoMemoryRepoName: String = ""
    @AppStorage(UserDefaultsKeys.RepoMemory.lastRefresh) private var repoMemoryLastRefresh: Double = 0
    @AppStorage(UserDefaultsKeys.RepoMemory.ready) private var repoMemoryReady: Bool = false

    @State private var aiKeyInput: String = ""
    @State private var editingProvider: AIProvider?
    @State private var connectionRefreshID: Int = 0
    @State private var localConfig: LocalLLMConfig = LocalLLMConfig()

    private var defaultProvider: AIProvider {
        AIProvider(rawValue: aiProviderRaw) ?? .none
    }

    private var mode: AIMode {
        AIMode(rawValue: aiModeRaw) ?? .efficient
    }

    private var providerConnections: [AIProviderConnectionInfo] {
        let _ = connectionRefreshID
        return AIProviderSupport.connectionInfo().filter { $0.provider != .local }
    }

    private var isDefaultProviderConnected: Bool {
        let _ = connectionRefreshID
        return AIProviderSupport.isConnected(provider: defaultProvider)
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

                if defaultProvider != .none && defaultProvider != .local && !isDefaultProviderConnected {
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
                            Text(row.lane.label)
                                .font(DesignSystem.Typography.labelBold)
                            Spacer()
                            Text(row.modelID)
                                .font(DesignSystem.Typography.monoLabel)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
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
                        }
                        .disabled(repoMemoryRepoName.isEmpty)

                        Spacer()

                        Button(L10n("settings.ai.repoMemory.clear")) {
                            NotificationCenter.default.post(name: .clearRepoMemory, object: nil)
                        }
                        .disabled(repoMemoryRepoName.isEmpty)
                    }
                }
            }

            Section(L10n("settings.ai.harness.title")) {
                Toggle(L10n("settings.ai.harness.toolsEnabled"), isOn: $chatToolsEnabled)
                Toggle(L10n("settings.ai.harness.allowEdits"), isOn: $chatAllowEdits)
                Toggle(L10n("settings.ai.harness.autoInject"), isOn: $chatAutoInject)

                if defaultProvider == .local {
                    let modelName = AIClient.loadLocalConfig()?.modelName ?? ""
                    let supported = AIProviderSupport.localModelSupportsTools(modelName)
                    Text(supported ? L10n("settings.ai.harness.toolCapability.supported") : L10n("settings.ai.harness.toolCapability.notSupported"))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
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
    }

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
