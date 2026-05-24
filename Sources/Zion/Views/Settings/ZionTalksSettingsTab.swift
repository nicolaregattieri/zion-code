import SwiftUI

// MARK: - TODO(T10): L10n — all string literals here need L10n() once keys are added in T10

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
                Text("Settings here apply only to the Zion Talks chat. For built-in AI actions (commit messages, PR descriptions, blame explainer), see AI Assistant.") // MARK: - TODO(T10): L10n
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
            }

            // MARK: Approval Policy (replaces Plan Mode + File Edits + Agentic Tier)
            ApprovalPolicySection()

            Section("General") { // MARK: - TODO(T10): L10n
                Toggle("Enable tool use", isOn: $toolsEnabled) // MARK: - TODO(T10): L10n
                Toggle("Auto-inject context", isOn: $autoInject) // MARK: - TODO(T10): L10n
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

            ContextBudgetSection()

            Section("Tool Bridge") { // MARK: - TODO(T10): L10n
                Toggle("Enable tool bridge", isOn: $toolBridge) // MARK: - TODO(T10): L10n
            }

            Section("Routing Policy") { // MARK: - TODO(T10): L10n
                RoutingPolicyEditor()
            }

            Section("Subscription CLI Failover") { // MARK: - TODO(T10): L10n
                Toggle("Allow CLI failover", isOn: $subscriptionFailover) // MARK: - TODO(T10): L10n
                Text("Enabling this allows the chat to fall back to a subscription CLI (Claude Code, Codex) when the selected provider is unavailable. Check your subscription terms before enabling.") // MARK: - TODO(T10): L10n
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(DesignSystem.Colors.warning)
            }
        }
        .formStyle(.grouped)
        .toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.actionPrimary))
        .tint(DesignSystem.Colors.actionPrimary)
    }
}
