import SwiftUI

struct AISettingsTab: View {
    @AppStorage("zion.aiProvider") private var aiProviderRaw: String = AIProvider.none.rawValue
    @AppStorage("zion.commitMessageStyle") private var commitStyleRaw: String = CommitMessageStyle.compact.rawValue
    @AppStorage("zion.autoExplainDiffs") private var autoExplainDiffs: Bool = false
    @AppStorage("zion.diffExplanationDepth") private var diffDepthRaw: String = DiffExplanationDepth.quick.rawValue

    @State private var aiKeyInput: String = ""
    @State private var isEditingKey: Bool = false
    @State private var savedKeyExists: Bool = false

    private var provider: AIProvider {
        AIProvider(rawValue: aiProviderRaw) ?? .none
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
                                .disabled(aiKeyInput.isEmpty)
                        }
                    }
                }
            }

            if provider != .none {
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(L10n("settings.ai.diffExplanation")) {
                    Toggle(L10n("settings.ai.autoExplain"), isOn: $autoExplainDiffs)

                    Picker(L10n("settings.ai.depth"), selection: $diffDepthRaw) {
                        ForEach(DiffExplanationDepth.allCases) { depth in
                            Text(depth.label).tag(depth.rawValue)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
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
