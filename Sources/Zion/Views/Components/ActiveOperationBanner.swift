import SwiftUI

struct ActiveOperationBanner: View {
    @Bindable var model: RepositoryViewModel

    var body: some View {
        if let operation = activeOperation {
            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                Image(systemName: operation.icon)
                    .foregroundStyle(DesignSystem.Colors.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(operation.title)
                        .font(DesignSystem.Typography.bodySmallBold)
                    if !operation.detail.isEmpty {
                        Text(operation.detail)
                            .font(DesignSystem.Typography.bodySmall)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Button(L10n("ops.active.continue")) {
                    continueOperation(operation.type)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(DesignSystem.Colors.actionPrimary)

                Button(L10n("ops.active.abort")) {
                    abortOperation(operation.type)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(DesignSystem.Colors.destructive)
            }
            .padding(DesignSystem.Spacing.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                    .fill(DesignSystem.Colors.warning.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                            .stroke(DesignSystem.Colors.warning.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }

    private struct OperationInfo {
        let type: OperationType
        let title: String
        let detail: String
        let icon: String
    }

    private enum OperationType {
        case merge, rebase, cherryPick
    }

    private var activeOperation: OperationInfo? {
        if model.isMerging {
            let conflictCount = model.conflictedFiles.count
            let detail = conflictCount > 0
                ? L10n("ops.active.conflicts", conflictCount)
                : ""
            return OperationInfo(type: .merge, title: L10n("ops.active.merge"), detail: detail, icon: "arrow.triangle.merge")
        }
        if model.isRebasing {
            let conflictCount = model.conflictedFiles.count
            let detail = conflictCount > 0
                ? L10n("ops.active.conflicts", conflictCount)
                : ""
            return OperationInfo(type: .rebase, title: L10n("ops.active.rebase"), detail: detail, icon: "arrow.triangle.branch")
        }
        if model.isCherryPicking {
            return OperationInfo(type: .cherryPick, title: L10n("ops.active.cherryPick"), detail: "", icon: "leaf.arrow.triangle.circlepath")
        }
        return nil
    }

    private func continueOperation(_ type: OperationType) {
        switch type {
        case .merge:
            model.runGitAction(label: "Continue merge", args: ["merge", "--continue"])
        case .rebase:
            model.runGitAction(label: "Continue rebase", args: ["rebase", "--continue"])
        case .cherryPick:
            model.runGitAction(label: "Continue cherry-pick", args: ["cherry-pick", "--continue"])
        }
    }

    private func abortOperation(_ type: OperationType) {
        switch type {
        case .merge:
            model.abortMerge()
        case .rebase:
            model.abortRebase()
        case .cherryPick:
            model.abortCherryPick()
        }
    }
}
