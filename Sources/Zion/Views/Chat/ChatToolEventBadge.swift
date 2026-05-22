import SwiftUI

// MARK: - ChatToolEventBadge

struct ChatToolEventBadge: View {

    let event: ChatToolEvent

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
            Image(systemName: iconName)
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Text(labelText)
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            trailingIndicator
        }
        .padding(.horizontal, DesignSystem.Spacing.compact)
        .padding(.vertical, 3)
        .background(DesignSystem.Colors.glassHover)
        .clipShape(Capsule())
    }

    // MARK: - Private

    private var iconName: String {
        let tool = event.name.lowercased()
        if tool.contains("bash") { return "terminal" }
        if tool.contains("read") { return "doc.text" }
        if tool.contains("edit") || tool.contains("write") { return "pencil" }
        if tool.contains("grep") || tool.contains("glob") { return "magnifyingglass" }
        if tool.contains("webfetch") || tool.contains("fetch") { return "globe" }
        return "hammer"
    }

    private var labelText: String {
        switch event.status {
        case .running:
            return L10n("chat.cli.tool.running", event.name)
        case .completed:
            return L10n("chat.cli.tool.completed", event.name)
        case .failed:
            return L10n("chat.cli.tool.failed", event.name)
        case .pending:
            return L10n("chat.cli.tool.running", event.name)
        }
    }

    @ViewBuilder
    private var trailingIndicator: some View {
        switch event.status {
        case .running, .pending:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 10, height: 10)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.success)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.error)
        }
    }
}
