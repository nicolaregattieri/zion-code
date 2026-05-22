import SwiftUI

// MARK: - ChatToolEventBadge

struct ChatToolEventBadge: View {

    let event: ChatToolEvent
    @State private var isExpanded: Bool = false

    private var canExpand: Bool {
        !(event.argsPreview.isEmpty) || !(event.output ?? "").isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                if canExpand { isExpanded.toggle() }
            } label: {
                HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                    Image(systemName: iconName)
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    Text(labelText)
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    if !event.argsPreview.isEmpty {
                        Text(event.argsPreview)
                            .font(DesignSystem.Typography.monoLabel)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    trailingIndicator

                    if canExpand {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(DesignSystem.Typography.label)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.compact)
                .padding(.vertical, 3)
                .background(DesignSystem.Colors.glassHover)
                .clipShape(Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            if isExpanded, let output = event.output, !output.isEmpty {
                ScrollView(.vertical) {
                    Text(output)
                        .font(DesignSystem.Typography.monoLabel)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 220)
                .background(DesignSystem.Colors.glassSubtle)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius))
            }
        }
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
