import SwiftUI

// MARK: - ToolEventBadge

struct ToolEventBadge: View {

    let event: ChatToolEvent

    // MARK: - Body

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
            Image(systemName: iconName)
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Text(labelText)
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: DesignSystem.Spacing.micro)

            statusView
        }
        .padding(.horizontal, DesignSystem.Spacing.compact)
        .padding(.vertical, DesignSystem.Spacing.micro)
        .background(
            Capsule()
                .fill(DesignSystem.Colors.glassHover)
                .overlay(
                    Capsule()
                        .strokeBorder(DesignSystem.Colors.glassBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Icon

    private var iconName: String {
        switch event.name.lowercased() {
        case let n where n.contains("read"):
            return "doc.text"
        case let n where n.contains("edit"):
            return "pencil"
        case let n where n.contains("write"):
            return "square.and.pencil"
        case let n where n.contains("bash"):
            return "terminal"
        case let n where n.contains("grep") || n.contains("glob"):
            return "magnifyingglass"
        default:
            return "gearshape"
        }
    }

    // MARK: - Label

    private var labelText: String {
        let preview = String(event.argsPreview.prefix(60))
        let name = event.name
        switch event.status {
        case .pending, .running:
            return L10n("chat.tool.running", name) + (preview.isEmpty ? "" : " — \(preview)")
        case .completed:
            return L10n("chat.tool.completed", name) + (preview.isEmpty ? "" : " — \(preview)")
        case .failed:
            return L10n("chat.tool.failed", name) + (preview.isEmpty ? "" : " — \(preview)")
        }
    }

    // MARK: - Status View

    @ViewBuilder
    private var statusView: some View {
        switch event.status {
        case .pending, .running:
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.6)
                .frame(width: DesignSystem.Spacing.compact * 2, height: DesignSystem.Spacing.compact * 2)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.success)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.destructive)
        }
    }
}
