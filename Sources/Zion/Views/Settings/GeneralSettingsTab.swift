import SwiftUI

struct GeneralSettingsTab: View {
    @AppStorage("zion.uiLanguage") private var uiLanguageRaw: String = AppLanguage.system.rawValue
    @AppStorage("zion.appearance") private var appearanceRaw: String = AppAppearance.system.rawValue
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
}
