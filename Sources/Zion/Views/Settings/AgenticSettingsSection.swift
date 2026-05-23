import SwiftUI

// MARK: - AgenticSettingsSection
// Embedded by ZionTalksSettingsTab inside its Form.
// Returns a Section — do NOT wrap in Form.

struct AgenticSettingsSection: View {

    // MARK: - TODO(T11): L10n — all string literals here need L10n() once keys are added in T11

    @AppStorage("chat.agent.tier") private var tierRaw: String = AgentApprovalTier.workspaceWrite.rawValue
    @AppStorage("chat.agent.maxSteps") private var maxSteps: Int = 25
    @AppStorage("chat.agent.bashAllowlist") private var bashAllowlist: String = ""
    @AppStorage("chat.agent.stopOnFirstError") private var stopOnFirstError: Bool = false

    private var tier: AgentApprovalTier {
        AgentApprovalTier(rawValue: tierRaw) ?? .workspaceWrite
    }

    var body: some View {
        Section("Agentic Loop") { // MARK: - TODO(T11): L10n — key: chat.settings.agenticLoop.title
            // MARK: Approval Tier
            Picker(
                "Approval tier", // MARK: - TODO(T11): L10n — key: chat.agent.tier.label
                selection: $tierRaw
            ) {
                Text("Read-only") // MARK: - TODO(T11): L10n — key: chat.agent.tier.readOnly
                    .tag(AgentApprovalTier.readOnly.rawValue)
                Text("Workspace write") // MARK: - TODO(T11): L10n — key: chat.agent.tier.workspaceWrite
                    .tag(AgentApprovalTier.workspaceWrite.rawValue)
                Text("Full access") // MARK: - TODO(T11): L10n — key: chat.agent.tier.fullAccess
                    .tag(AgentApprovalTier.fullAccess.rawValue)
            }

            if tier == .fullAccess {
                Text("Full access lets the agent run any shell command without asking. Only enable if you trust the model and understand the risks.") // MARK: - TODO(T11): L10n — key: chat.agent.tier.fullAccess.warning
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(DesignSystem.Colors.warning)
            }

            // MARK: Max Steps
            Stepper(
                value: $maxSteps,
                in: 5...100,
                step: 1
            ) {
                HStack {
                    Text("Max steps") // MARK: - TODO(T11): L10n — key: chat.agent.maxSteps.label
                    Spacer()
                    Text("\(maxSteps)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            // MARK: Bash Allowlist
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.compact) {
                Text("Bash allowlist") // MARK: - TODO(T11): L10n — key: chat.agent.bashAllowlist.label
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundStyle(.secondary)
                TextEditor(text: $bashAllowlist)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 84) // ~6 lines at default line height
                    .overlay(
                        Group {
                            if bashAllowlist.isEmpty {
                                Text("Newline-separated commands. Leave empty for defaults.") // MARK: - TODO(T11): L10n — key: chat.agent.bashAllowlist.placeholder
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                                    .padding(.horizontal, DesignSystem.Spacing.compact)
                                    .padding(.vertical, DesignSystem.Spacing.compact)
                                    .allowsHitTesting(false)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            }
                        }
                    )
                    .background(DesignSystem.Colors.glassSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
            }

            // MARK: Stop On First Error
            Toggle(
                "Stop on first error", // MARK: - TODO(T11): L10n — key: chat.agent.stopOnFirstError.label
                isOn: $stopOnFirstError
            )
        }
    }
}
