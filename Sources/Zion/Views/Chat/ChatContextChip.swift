import SwiftUI

/// Phase 6 — single auto-context chip. Shows `<basename>:<lineStart>-<lineEnd>`
/// with a dismiss button. Tooltip carries the full path. Dismiss removes the
/// chip from the upcoming message's injected context.
struct ChatContextChip: View {

    let hit: RAGHit
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(DesignSystem.Typography.meta)
                .foregroundStyle(DesignSystem.Colors.ai)
            Text(label)
                .font(DesignSystem.Typography.monoLabel)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 16, minHeight: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n("chat.context.chip.remove"))
        }
        .padding(.horizontal, DesignSystem.Spacing.compact)
        .padding(.vertical, 3)
        .background(DesignSystem.Colors.glassSubtle)
        .clipShape(Capsule())
        .overlay(
            Capsule().strokeBorder(DesignSystem.Colors.glassStroke, lineWidth: 1)
        )
        .help(String(
            format: L10n("chat.context.chip.tooltip"),
            hit.chunk.path,
            "\(hit.chunk.startLine)-\(hit.chunk.endLine)"
        ))
    }

    private var label: String {
        let base = (hit.chunk.path as NSString).lastPathComponent
        return "\(base):\(hit.chunk.startLine)-\(hit.chunk.endLine)"
    }
}
