import SwiftUI

struct GeneralSettingsTab: View {
    @AppStorage("zion.uiLanguage") private var uiLanguageRaw: String = AppLanguage.system.rawValue
    @AppStorage("zion.appearance") private var appearanceRaw: String = AppAppearance.system.rawValue
    @AppStorage("zion.preferredTerminal") private var preferredTerminalRaw: String = ExternalTerminal.terminal.rawValue
    @AppStorage("zion.customTerminalPath") private var customTerminalPath: String = ""
    @AppStorage("zion.confirmationMode") private var confirmationModeRaw: String = ConfirmationMode.destructiveOnly.rawValue

    var body: some View {
        Form {
            // Interface
            Section(L10n("settings.general.interface")) {
                Picker(L10n("Idioma"), selection: $uiLanguageRaw) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.label).tag(lang.rawValue)
                    }
                }

                Picker(L10n("Aparencia"), selection: $appearanceRaw) {
                    ForEach(AppAppearance.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
            }

            // Tools
            Section(L10n("settings.general.tools")) {
                Picker(L10n("Terminal Externo"), selection: $preferredTerminalRaw) {
                    ForEach(ExternalTerminal.allCases) { term in
                        Text(term.label).tag(term.rawValue)
                    }
                }
                .onChange(of: preferredTerminalRaw) { _, val in
                    if val == "custom" { pickCustomApp() }
                }

                if preferredTerminalRaw == "custom" && !customTerminalPath.isEmpty {
                    HStack {
                        Text(L10n("settings.general.customPath"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(URL(fileURLWithPath: customTerminalPath).lastPathComponent)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Safety
            Section(L10n("settings.general.safety")) {
                Picker(L10n("settings.general.confirmation"), selection: $confirmationModeRaw) {
                    ForEach(ConfirmationMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func pickCustomApp() {
        let panel = NSOpenPanel()
        panel.message = L10n("Selecione seu Terminal favorito")
        panel.allowedContentTypes = [.application, .aliasFile]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            customTerminalPath = url.path
        } else {
            preferredTerminalRaw = ExternalTerminal.terminal.rawValue
        }
    }
}
