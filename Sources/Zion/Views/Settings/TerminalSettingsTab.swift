import SwiftUI

struct TerminalSettingsTab: View {
    @AppStorage("terminal.scrollbackSize") private var scrollbackSize: Int = 5000
    @AppStorage("terminal.bellMode") private var bellMode: String = "system"
    @AppStorage("terminal.openHyperlinks") private var openHyperlinks: Bool = true
    @AppStorage("terminal.imageRendering") private var imageRendering: Bool = true
    @AppStorage("terminal.copyOnSelect") private var copyOnSelect: Bool = false

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
                    .font(.caption)
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
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(L10n("settings.terminal.imageRendering"), isOn: $imageRendering)

                Text(L10n("settings.terminal.imageRendering.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L10n("settings.terminal.advanced"))
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
    }
}
