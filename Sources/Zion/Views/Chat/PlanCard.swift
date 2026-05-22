import SwiftUI

// MARK: - ChatPlanAction

enum ChatPlanAction: Equatable {
    case apply
    case reject
    case reedit(String)
}

// MARK: - PlanCard

struct PlanCard: View {
    let plan: ChatPlan
    let isStreaming: Bool
    var onAction: (ChatPlanAction) -> Void

    @State private var isEditing: Bool = false
    @State private var draftXML: String = ""

    var body: some View {
        GlassCard(borderTint: DesignSystem.Colors.ai.opacity(0.4)) {
            planHeader
            Divider()
                .overlay(DesignSystem.Colors.glassBorderDark)
            stepsContent
            if isEditing {
                editSection
            } else {
                footerButtons
            }
        }
    }

    // MARK: - Subviews

    private var planHeader: some View {
        HStack(spacing: DesignSystem.Spacing.iconTextGap) {
            Image(systemName: "list.bullet.clipboard")
                .font(DesignSystem.Typography.subtitle)
                .foregroundStyle(DesignSystem.Colors.ai)
            // MARK: - TODO(T10): L10n
            Text("Plan")
                .font(DesignSystem.Typography.bodySemibold)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Spacer()
            // Steps count badge
            Text("\(plan.steps.count)")
                .font(DesignSystem.Typography.labelBold)
                .foregroundStyle(DesignSystem.Colors.ai)
                .padding(.horizontal, DesignSystem.Spacing.compact)
                .padding(.vertical, DesignSystem.Spacing.micro)
                .background(DesignSystem.Colors.ai.opacity(0.15))
                .clipShape(Capsule())
        }
    }

    private var stepsContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.standard) {
            ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                PlanStepRow(index: index + 1, step: step)
            }
        }
    }

    private var editSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.standard) {
            Divider()
                .overlay(DesignSystem.Colors.glassBorderDark)
            TextEditor(text: $draftXML)
                .font(DesignSystem.Typography.monoSmall)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .background(DesignSystem.Colors.glassInset)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous))
            HStack {
                Spacer()
                // MARK: - TODO(T10): L10n
                Button("Save") {
                    onAction(.reedit(draftXML))
                    isEditing = false
                }
                .font(DesignSystem.Typography.bodySemibold)
                .foregroundStyle(DesignSystem.Colors.ai)
                .buttonStyle(.plain)
                .padding(.horizontal, DesignSystem.Spacing.standard)
                .padding(.vertical, DesignSystem.Spacing.compact)
                .background(DesignSystem.Colors.ai.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous))
            }
        }
    }

    private var footerButtons: some View {
        HStack(spacing: DesignSystem.Spacing.standard) {
            // MARK: - TODO(T10): L10n
            Button("Apply") {
                applyTapped()
            }
            .font(DesignSystem.Typography.bodySemibold)
            .foregroundStyle(isStreaming ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.success)
            .buttonStyle(.plain)
            .padding(.horizontal, DesignSystem.Spacing.standard)
            .padding(.vertical, DesignSystem.Spacing.compact)
            .background(isStreaming
                ? DesignSystem.Colors.glassSubtle
                : DesignSystem.Colors.success.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous))
            .disabled(isStreaming)

            // MARK: - TODO(T10): L10n
            Button("Reject") {
                rejectTapped()
            }
            .font(DesignSystem.Typography.body)
            .foregroundStyle(DesignSystem.Colors.destructive)
            .buttonStyle(.plain)
            .padding(.horizontal, DesignSystem.Spacing.standard)
            .padding(.vertical, DesignSystem.Spacing.compact)
            .background(DesignSystem.Colors.destructiveBg)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous))

            Spacer()

            // MARK: - TODO(T10): L10n
            Button("Edit") {
                editTapped()
            }
            .font(DesignSystem.Typography.body)
            .foregroundStyle(DesignSystem.Colors.textSecondary)
            .buttonStyle(.plain)
        }
    }

    // MARK: - Action Helpers (testable)

    internal func applyTapped() {
        guard !isStreaming else { return }
        onAction(.apply)
    }

    internal func rejectTapped() {
        onAction(.reject)
    }

    internal func editTapped() {
        draftXML = plan.rawXML
        isEditing = true
    }

    internal func saveTapped(xml: String) {
        onAction(.reedit(xml))
        isEditing = false
    }
}

// MARK: - PlanStepRow

private struct PlanStepRow: View {
    let index: Int
    let step: ChatPlanStep

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.standard) {
            // Step number badge
            Text("\(index)")
                .font(DesignSystem.Typography.monoLabelBold)
                .foregroundStyle(DesignSystem.Colors.ai)
                .frame(width: 20, height: 20)
                .background(DesignSystem.Colors.ai.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.micro) {
                if let commitMsg = step.commitMessage, !commitMsg.isEmpty {
                    Text(commitMsg)
                        .font(DesignSystem.Typography.monoBodyBold)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                }
                if !step.filePaths.isEmpty {
                    Text(step.filePaths.joined(separator: ", "))
                        .font(DesignSystem.Typography.monoSmall)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                if !step.summary.isEmpty {
                    Text(step.summary)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
        }
    }
}
