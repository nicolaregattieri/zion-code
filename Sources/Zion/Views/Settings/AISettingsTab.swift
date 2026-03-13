import SwiftUI

struct AISettingsTab: View {
    @AppStorage("zion.aiProvider") private var aiProviderRaw: String = AIProvider.none.rawValue
    @AppStorage("zion.aiMode") private var aiModeRaw: String = AIMode.efficient.rawValue
    @AppStorage("zion.commitMessageStyle") private var commitStyleRaw: String = CommitMessageStyle.compact.rawValue
    @AppStorage("zion.preCommitReview") private var preCommitReviewEnabled: Bool = false
    @AppStorage("zion.aiTransferSupportHints") private var aiTransferSupportHints: Bool = true
    @AppStorage("zion.repoMemory.activeRepoName") private var repoMemoryRepoName: String = ""
    @AppStorage("zion.repoMemory.lastRefresh") private var repoMemoryLastRefresh: Double = 0
    @AppStorage("zion.repoMemory.ready") private var repoMemoryReady: Bool = false

    @State private var aiKeyInput: String = ""
    @State private var isEditingKey: Bool = false
    @State private var savedKeyExists: Bool = false

    private var provider: AIProvider {
        AIProvider(rawValue: aiProviderRaw) ?? .none
    }

    private var mode: AIMode {
        AIMode(rawValue: aiModeRaw) ?? .efficient
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
            Section(L10n("settings.ai.provider")) {
                Picker(L10n("settings.ai.provider"), selection: $aiProviderRaw) {
                    ForEach(AIProvider.allCases) { p in
                        Text(p.label).tag(p.rawValue)
                    }
                }
                .onChange(of: aiProviderRaw) { _, _ in
                    isEditingKey = false
                    aiKeyInput = ""
                    checkSavedKey()
                }

                if provider != .none {
                    if savedKeyExists && !isEditingKey {
                        HStack {
                            Label(L10n("Chave registrada"), systemImage: "lock.fill")
                                .foregroundStyle(DesignSystem.Colors.success)
                            Spacer()
                            Button(L10n("Alterar")) {
                                aiKeyInput = AIClient.loadAPIKey(for: provider) ?? ""
                                isEditingKey = true
                            }
                            .buttonStyle(.plain)
                            .cursorArrow()
                            .foregroundStyle(DesignSystem.Colors.info)
                        }
                    } else {
                        SecureField(L10n("Chave de API"), text: $aiKeyInput)
                            .onSubmit { saveKey() }

                        HStack {
                            if isEditingKey {
                                Button(L10n("Cancelar")) {
                                    isEditingKey = false
                                    aiKeyInput = ""
                                }
                            }
                            Spacer()
                            Button(L10n("Salvar")) { saveKey() }
                                .buttonStyle(.borderedProminent)
                                .tint(DesignSystem.Colors.actionPrimary)
                                .disabled(aiKeyInput.isEmpty)
                        }
                    }
                }
            }

            if provider != .none {
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
                    ForEach(AIModelCatalogService.mappingRows(for: provider, mode: mode), id: \.lane) { row in
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
        .onAppear { checkSavedKey() }
    }

    private func checkSavedKey() {
        savedKeyExists = AIClient.loadAPIKey(for: provider) != nil
    }

    private func saveKey() {
        guard !aiKeyInput.isEmpty else { return }
        AIClient.saveAPIKey(aiKeyInput, for: provider)
        isEditingKey = false
        aiKeyInput = ""
        savedKeyExists = true
    }
}
