import SwiftUI

// MARK: - AgenticSettingsSection
// Embedded by ZionTalksSettingsTab inside its Form.
// Returns a Section — do NOT wrap in Form.

struct AgenticSettingsSection: View {

    @AppStorage("chat.agent.tier") private var tierRaw: String = AgentApprovalTier.workspaceWrite.rawValue
    @AppStorage("chat.agent.maxSteps") private var maxSteps: Int = 25
    @AppStorage("chat.agent.bashAllowlist") private var bashAllowlist: String = ""
    @AppStorage("chat.agent.stopOnFirstError") private var stopOnFirstError: Bool = false

    private var tier: AgentApprovalTier {
        AgentApprovalTier(rawValue: tierRaw) ?? .workspaceWrite
    }

    var body: some View {
        Section(L10n("chat.settings.agenticLoop.title")) {
            // MARK: Approval Tier
            Picker(
                L10n("chat.agent.tier.label"),
                selection: $tierRaw
            ) {
                Text(L10n("chat.agent.tier.readOnly"))
                    .tag(AgentApprovalTier.readOnly.rawValue)
                Text(L10n("chat.agent.tier.workspaceWrite"))
                    .tag(AgentApprovalTier.workspaceWrite.rawValue)
                Text(L10n("chat.agent.tier.fullAccess"))
                    .tag(AgentApprovalTier.fullAccess.rawValue)
            }

            if tier == .fullAccess {
                Text(L10n("chat.agent.tier.fullAccess.warning"))
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
                    Text(L10n("chat.agent.maxSteps.label"))
                    Spacer()
                    Text("\(maxSteps)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            // MARK: Bash Allowlist
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.compact) {
                Text(L10n("chat.agent.bashAllowlist.label"))
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundStyle(.secondary)
                TextEditor(text: $bashAllowlist)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 84) // ~6 lines at default line height
                    .overlay(
                        Group {
                            if bashAllowlist.isEmpty {
                                Text(L10n("chat.agent.bashAllowlist.placeholder"))
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
                L10n("chat.agent.stopOnFirstError.label"),
                isOn: $stopOnFirstError
            )
        }
    }
}
