import SwiftUI

// MARK: - MultiFileDiffSummaryState

/// Pure-logic state model for MultiFileDiffSummary.
/// Extracted so XCTest can exercise behaviour without SwiftUI view hierarchy.
@MainActor
final class MultiFileDiffSummaryState: ObservableObject {

    let blocks: [EditBlock]

    init(blocks: [EditBlock]) {
        self.blocks = blocks
    }

    /// Returns true when the summary card should be rendered (>= 2 blocks).
    var shouldRender: Bool { blocks.count >= 2 }

    /// Returns true when the per-file cards should collapse to summary lines (>= 4 blocks).
    var collapsedRendering: Bool { blocks.count >= 4 }

    /// L10n key for the summary header.
    var headerKey: String { "chat.multifileDiff.header" }

    /// Calls `applyAction` on each block in order.
    func approveAll(applyAction: (EditBlock) -> Void) {
        for block in blocks {
            applyAction(block)
        }
    }

    /// Calls `cancelAction` once.
    func rejectAll(cancelAction: () -> Void) {
        cancelAction()
    }
}

// MARK: - MultiFileDiffSummary

struct MultiFileDiffSummary: View {

    let blocks: [EditBlock]
    let onReviewAll: () -> Void
    let onApproveAll: () -> Void
    let onRejectAll: () -> Void

    @State private var isExpanded: Bool = true

    var body: some View {
        GlassCard(borderTint: DesignSystem.Colors.ai.opacity(0.4)) {
            summaryHeader
            if isExpanded {
                fileList
            }
            buttonRow
        }
    }

    // MARK: - Subviews

    private var summaryHeader: some View {
        HStack(spacing: DesignSystem.Spacing.iconTextGap) {
            Image(systemName: "folder.fill")
                .font(DesignSystem.Typography.subtitle)
                .foregroundStyle(DesignSystem.Colors.ai)
            // MARK: - TODO(T11): L10n
            Text(L10n("chat.multifileDiff.header", "\(blocks.count)"))
                .font(DesignSystem.Typography.bodySemibold)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Spacer()
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.micro) {
            ForEach(blocks) { block in
                fileRow(block: block)
            }
        }
        .padding(.vertical, DesignSystem.Spacing.micro)
    }

    private func fileRow(block: EditBlock) -> some View {
        HStack(spacing: DesignSystem.Spacing.iconTextGap) {
            Image(systemName: "doc.text")
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            Text(block.path)
                .font(DesignSystem.Typography.monoSmall)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            let addCount = block.replace.components(separatedBy: "\n").count
            let delCount = block.search.components(separatedBy: "\n").count
            HStack(spacing: DesignSystem.Spacing.compact) {
                Text("+\(addCount)")
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(DesignSystem.Colors.success)
                Text("-\(delCount)")
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(DesignSystem.Colors.error)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.compact)
        .padding(.vertical, DesignSystem.Spacing.micro)
        .background(DesignSystem.Colors.glassInset)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous))
    }

    private var buttonRow: some View {
        HStack(spacing: DesignSystem.Spacing.standard) {
            // Review all — TODO(P12.5): open diff viewer sheet
            Button(L10n("chat.multifileDiff.reviewAll")) {
                onReviewAll()
            }
            .font(DesignSystem.Typography.body)
            .foregroundStyle(DesignSystem.Colors.ai)
            .buttonStyle(.plain)
            .padding(.horizontal, DesignSystem.Spacing.standard)
            .padding(.vertical, DesignSystem.Spacing.compact)
            .background(DesignSystem.Colors.ai.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous))

            Button(L10n("chat.multifileDiff.approveAll")) {
                approveAllTapped()
            }
            .font(DesignSystem.Typography.bodySemibold)
            .foregroundStyle(DesignSystem.Colors.success)
            .buttonStyle(.plain)
            .padding(.horizontal, DesignSystem.Spacing.standard)
            .padding(.vertical, DesignSystem.Spacing.compact)
            .background(DesignSystem.Colors.success.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous))

            Button(L10n("chat.multifileDiff.rejectAll")) {
                rejectAllTapped()
            }
            .font(DesignSystem.Typography.body)
            .foregroundStyle(DesignSystem.Colors.destructive)
            .buttonStyle(.plain)
            .padding(.horizontal, DesignSystem.Spacing.standard)
            .padding(.vertical, DesignSystem.Spacing.compact)
            .background(DesignSystem.Colors.destructiveBg)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous))

            Spacer()
        }
    }

    // MARK: - Action Helpers (testable)

    internal func approveAllTapped() {
        onApproveAll()
    }

    internal func rejectAllTapped() {
        onRejectAll()
    }
}
