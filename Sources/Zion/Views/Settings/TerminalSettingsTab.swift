import Speech
import SwiftUI

struct TerminalSettingsTab: View {
    @AppStorage("terminal.scrollbackSize") private var scrollbackSize: Int = 5000
    @AppStorage("terminal.bellMode") private var bellMode: String = "system"
    @AppStorage("terminal.openHyperlinks") private var openHyperlinks: Bool = true
    @AppStorage("terminal.copyOnSelect") private var copyOnSelect: Bool = false
    @AppStorage("terminal.aiImageDisplay") private var aiImageDisplay: Bool = false
    @AppStorage("speech.engine") private var speechEngine: String = "apple"
    @AppStorage("speech.locale") private var speechLocale: String = Locale.current.identifier

    private var isWhisperAvailable: Bool {
        SpeechEngineSupport.isWhisperAvailable()
    }

    private var speechEngineSelection: Binding<String> {
        Binding(
            get: {
                SpeechEngineSupport.effectiveEngine(storedValue: speechEngine).rawValue
            },
            set: { newValue in
                let nextValue = SpeechEngineSupport.effectiveEngine(storedValue: newValue).rawValue
                speechEngine = nextValue
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker(L10n("settings.terminal.scrollback"), selection: $scrollbackSize) {
                    Text("500").tag(500)
                    Text("1,000").tag(1_000)
                    Text("5,000").tag(5_000)
                    Text("10,000").tag(10_000)
                    Text(L10n("settings.terminal.scrollback.unlimited")).tag(Int.max)
                }

                Text(L10n("settings.terminal.scrollback.hint"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L10n("settings.terminal.buffer"))
            }

            Section {
                Picker(L10n("settings.terminal.bellMode"), selection: $bellMode) {
                    Text(L10n("settings.terminal.bell.off")).tag("off")
                    Text(L10n("settings.terminal.bell.visual")).tag("visual")
                    Text(L10n("settings.terminal.bell.system")).tag("system")
                }
            } header: {
                Text(L10n("settings.terminal.bell"))
            }

            Section {
                Toggle(L10n("settings.terminal.openHyperlinks"), isOn: $openHyperlinks)

                Text(L10n("settings.terminal.openHyperlinks.hint"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)

                Toggle(L10n("settings.terminal.aiImageDisplay"), isOn: $aiImageDisplay)

                Text(L10n("settings.terminal.aiImageDisplay.hint"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L10n("settings.terminal.advanced"))
            }

            Section {
                Picker(L10n("speech.engine"), selection: speechEngineSelection) {
                    Text(L10n("speech.engine.apple")).tag("apple")
                    Text(L10n("speech.engine.whisper")).tag("whisper")
                        .disabled(!isWhisperAvailable)
                }

                Text(L10n("settings.speech.engine.hint"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)

                if !isWhisperAvailable {
                    Label(L10n("settings.speech.engine.whisperUnavailable"), systemImage: "exclamationmark.triangle.fill")
                        .font(DesignSystem.Typography.labelMedium)
                        .foregroundStyle(DesignSystem.Colors.warning)

                    SettingsLink {
                        Label(L10n("settings.speech.engine.configureOpenAI"), systemImage: "sparkles")
                            .font(DesignSystem.Typography.label)
                    }
                    .buttonStyle(.bordered)
                    .simultaneousGesture(TapGesture().onEnded {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            NotificationCenter.default.post(name: .openAISettings, object: nil)
                        }
                    })
                }

                Picker(L10n("speech.language"), selection: $speechLocale) {
                    ForEach(SFSpeechRecognizer.supportedLocales().sorted(by: { $0.identifier < $1.identifier }), id: \.identifier) { locale in
                        Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                            .tag(locale.identifier)
                    }
                }
            } header: {
                Text(L10n("speech.button.tooltip"))
            }

            Section {
                Toggle(L10n("settings.terminal.copyOnSelect"), isOn: $copyOnSelect)
            } header: {
                Text(L10n("settings.terminal.selection"))
            }
        }
        .formStyle(.grouped)
        .toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.actionPrimary))
        .tint(DesignSystem.Colors.actionPrimary)
        .onAppear {
            let effectiveEngine = SpeechEngineSupport.effectiveEngine(storedValue: speechEngine)
            if speechEngine != effectiveEngine.rawValue {
                speechEngine = effectiveEngine.rawValue
            }
        }
        .onChange(of: aiImageDisplay) { _, _ in
            TerminalTabView.syncInstalledTerminalHelpersForCurrentSettings()
        }
    }
}
