import SwiftUI

// MARK: - ApprovalPolicySection
// Embedded by ZionTalksSettingsTab inside its Form.
// Returns a Section — do NOT wrap in Form.
// MARK: - TODO(T11): L10n — new keys below need locale entries

struct ApprovalPolicySection: View {
    @AppStorage(ApprovalPolicy.storageKey) private var policyRaw: String = ApprovalPolicy.autoSafe.rawValue
    @State private var showAdvanced = false

    private var policy: ApprovalPolicy {
        ApprovalPolicy(rawValue: policyRaw) ?? .autoSafe
    }

    var body: some View {
        Section(L10n("chat.approvalPolicy.section.title")) {
            Picker(L10n("chat.approvalPolicy.picker.label"), selection: $policyRaw) {
                ForEach(ApprovalPolicy.allCases) { p in
                    Text(p.label).tag(p.rawValue)
                }
            }
            .pickerStyle(.radioGroup)

            Text(policy.description)
                .font(DesignSystem.Typography.label)
                .foregroundStyle(.secondary)

            if policy == .yolo {
                HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DesignSystem.Colors.warning)
                    Text(L10n("chat.approvalPolicy.yolo.warning"))
                        .font(DesignSystem.Typography.labelMedium)
                        .foregroundStyle(DesignSystem.Colors.warning)
                }
            }

            DisclosureGroup(L10n("chat.approvalPolicy.advanced"), isExpanded: $showAdvanced) {
                advancedControls
            }
        }
    }

    @ViewBuilder
    private var advancedControls: some View {
        HStack {
            Text(L10n("chat.approvalPolicy.advanced.bashTier"))
            Spacer()
            Text(policy.bashTier.rawValue)
                .foregroundStyle(.secondary)
        }
        HStack {
            Text(L10n("chat.approvalPolicy.advanced.autoCommit"))
            Spacer()
            Text(policy.autoCommit ? L10n("Sim") : L10n("Não"))
                .foregroundStyle(.secondary)
        }
        HStack {
            Text(L10n("chat.approvalPolicy.advanced.asksDestructive"))
            Spacer()
            Text(policy.asksDestructive ? L10n("Sim") : L10n("Não"))
                .foregroundStyle(.secondary)
        }
    }
}
