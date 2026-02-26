import SwiftUI

struct GeneralSettingsTab: View {
    @AppStorage("zion.uiLanguage") private var uiLanguageRaw: String = AppLanguage.system.rawValue
    @AppStorage("zion.appearance") private var appearanceRaw: String = AppAppearance.system.rawValue
    @AppStorage("zion.confirmationMode") private var confirmationModeRaw: String = ConfirmationMode.destructiveOnly.rawValue
    @AppStorage("zion.zionModeEnabled") private var zionModeEnabled: Bool = false
    @State private var glowPulse: Bool = false

    var body: some View {
        Form {
            // Zion Mode
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(
                            zionModeEnabled
                                ? AnyShapeStyle(.linearGradient(
                                    colors: [DesignSystem.ZionMode.neonMagenta, DesignSystem.ZionMode.neonGold],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                : AnyShapeStyle(.linearGradient(
                                    colors: [.purple, .orange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                        )
                        .frame(width: 28, height: 28)
                        .background(
                            zionModeEnabled
                                ? LinearGradient(
                                    colors: [DesignSystem.ZionMode.neonMagenta.opacity(0.15), DesignSystem.ZionMode.neonGold.opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [.purple.opacity(0.15), .orange.opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
                        .shadow(
                            color: zionModeEnabled ? DesignSystem.ZionMode.neonMagenta.opacity(glowPulse ? 0.35 : 0.15) : .clear,
                            radius: glowPulse ? 6 : 3
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Zion Mode")
                            .font(.system(size: 13, weight: .bold))
                        Text(L10n("settings.zionMode.subtitle"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $zionModeEnabled)
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: zionModeEnabled ? DesignSystem.ZionMode.neonMagenta : .purple))
                }
            }

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
        .onAppear {
            if zionModeEnabled {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    glowPulse = true
                }
            }
        }
        .onChange(of: zionModeEnabled) { _, enabled in
            if enabled {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    glowPulse = true
                }
            } else {
                withAnimation(.easeInOut(duration: 0.3)) {
                    glowPulse = false
                }
            }
        }
    }
}
