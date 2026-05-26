import SwiftUI

struct ZionTalksSettingsTab: View {
    @AppStorage("chat.autoInject") private var autoInject: Bool = true
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
                Toggle(L10n("chat.settings.autoInject"), isOn: $autoInject)
                Text(L10n("chat.settings.autoInject.hint"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

            // Tool Bridge toggle removed from the UI in this prune — keeping
            // a working tool-bridge ON is part of "Zion Talks is LLM-agnostic"
            // and disabling it would silently cripple native API providers.
            // The storage key (`chat.providers.toolBridge`) and the
            // ZionToolBridge runtime gate stay in place so developers /
            // debugging sessions can flip it via `defaults write` if needed.

            Section(L10n("chat.settings.routingPolicy")) {
                RoutingPolicyEditor()
            }

            // Subscription-CLI failover toggle removed here — it already
            // lives in Settings → AI → "Routing & Safety" with a clearer
            // hint. Two duplicate toggles for the same UserDefault was
            // confusing (and shipped with DIFFERENT defaults, false here vs
            // true there). The AISettingsTab control is authoritative.
        }
        .formStyle(.grouped)
        .toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.actionPrimary))
        .tint(DesignSystem.Colors.actionPrimary)
    }
}
