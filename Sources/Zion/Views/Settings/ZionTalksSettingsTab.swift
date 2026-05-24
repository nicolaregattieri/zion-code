import SwiftUI

struct ZionTalksSettingsTab: View {
    @AppStorage("chat.toolsEnabled") private var toolsEnabled: Bool = true
    @AppStorage("chat.autoInject") private var autoInject: Bool = true
    @AppStorage("chat.providers.toolBridge") private var toolBridge: Bool = true
    @AppStorage("chat.routing.subscriptionFailover") private var subscriptionFailover: Bool = false
    @AppStorage(ZionTalksAppearance.fontSizeKey) private var fontSizePx: Int = ZionTalksAppearance.defaultFontSizePx
    @AppStorage(ZionTalksAppearance.lineSpacingKey) private var lineSpacingPx: Int = ZionTalksAppearance.defaultLineSpacingPx

    var body: some View {
        Form {
            Section {
                Text(L10n("chat.settings.tab.intro"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
            }

            ApprovalPolicySection()

            Section(L10n("chat.settings.general")) {
                Toggle(L10n("chat.settings.toolsEnabled"), isOn: $toolsEnabled)
                Toggle(L10n("chat.settings.autoInject"), isOn: $autoInject)
            }

            Section(L10n("chat.settings.appearance")) {
                Stepper(value: $fontSizePx, in: ZionTalksAppearance.minFontSizePx...ZionTalksAppearance.maxFontSizePx) {
                    HStack {
                        Text(L10n("chat.settings.fontSize"))
                        Spacer()
                        Text(L10n("chat.settings.px", "\(fontSizePx)"))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Stepper(value: $lineSpacingPx, in: ZionTalksAppearance.minLineSpacingPx...ZionTalksAppearance.maxLineSpacingPx) {
                    HStack {
                        Text(L10n("chat.settings.lineSpacing"))
                        Spacer()
                        Text(L10n("chat.settings.px", "\(lineSpacingPx)"))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Text(L10n("chat.settings.fontSize.hint"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
            }

            AgenticSettingsSection()

            SmartContextSettingsSection()

            SkillsSettingsSection()

            MCPServersSettingsSection()

            ContextBudgetSection()

            UsageSettingsSection()

            Section(L10n("chat.settings.toolBridge")) {
                Toggle(L10n("chat.settings.toolBridge.toggle"), isOn: $toolBridge)
            }

            Section(L10n("chat.settings.routingPolicy")) {
                RoutingPolicyEditor()
            }

            Section(L10n("chat.settings.cliFailover")) {
                Toggle(L10n("chat.settings.cliFailover.toggle"), isOn: $subscriptionFailover)
                Text(L10n("chat.settings.cliFailover.warning"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(DesignSystem.Colors.warning)
            }
        }
        .formStyle(.grouped)
        .toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.actionPrimary))
        .tint(DesignSystem.Colors.actionPrimary)
    }
}
