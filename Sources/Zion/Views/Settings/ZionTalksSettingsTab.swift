import SwiftUI

// MARK: - TODO(T10): L10n — all string literals here need L10n() once keys are added in T10

struct ZionTalksSettingsTab: View {
    @AppStorage("chat.cliAllowEdits") private var cliAllowEdits: Bool = false
    @AppStorage("chat.toolsEnabled") private var toolsEnabled: Bool = true
    @AppStorage("chat.autoInject") private var autoInject: Bool = true
    @AppStorage("chat.providers.toolBridge") private var toolBridge: Bool = true
    @AppStorage("chat.plan.mode") private var planModeRaw: String = "planFirst"
    @AppStorage("chat.editHarness.enabled") private var editHarnessEnabled: Bool = true
    @AppStorage("chat.editHarness.autoCommit") private var editHarnessAutoCommit: Bool = true
    @AppStorage("chat.editHarness.preferNativeTool") private var editHarnessPreferNativeTool: Bool = true
    @AppStorage("chat.routing.subscriptionFailover") private var subscriptionFailover: Bool = false

    var body: some View {
        Form {
            Section {
                Text("Settings here apply only to the Zion Talks chat. For built-in AI actions (commit messages, PR descriptions, blame explainer), see AI Assistant.") // MARK: - TODO(T10): L10n
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
            }

            Section("General") { // MARK: - TODO(T10): L10n
                Toggle("Enable tool use", isOn: $toolsEnabled) // MARK: - TODO(T10): L10n
                Toggle("Auto-inject context", isOn: $autoInject) // MARK: - TODO(T10): L10n
            }

            Section("File Edits") { // MARK: - TODO(T10): L10n
                Toggle("Allow CLI file edits", isOn: $cliAllowEdits) // MARK: - TODO(T10): L10n
                Toggle("Enable edit harness", isOn: $editHarnessEnabled) // MARK: - TODO(T10): L10n
                Toggle("Auto-commit edits", isOn: $editHarnessAutoCommit) // MARK: - TODO(T10): L10n
                Toggle("Prefer native diff tool", isOn: $editHarnessPreferNativeTool) // MARK: - TODO(T10): L10n
            }

            Section("Plan Mode") { // MARK: - TODO(T10): L10n
                Picker("Plan mode", selection: $planModeRaw) { // MARK: - TODO(T10): L10n
                    Text("Plan first").tag("planFirst") // MARK: - TODO(T10): L10n
                    Text("Auto-apply").tag("autoApply") // MARK: - TODO(T10): L10n
                }
                .pickerStyle(.segmented)
            }

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
