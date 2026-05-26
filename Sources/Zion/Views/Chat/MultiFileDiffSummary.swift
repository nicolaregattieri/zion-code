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
    @State private var isReviewSheetPresented: Bool = false

    /// Counts derived from the current block state, recomputed every render so
    /// the summary reflects progress as applyAllEdits walks the list.
    private var appliedCount: Int {
        blocks.filter { $0.appliedAt != nil }.count
    }
    private var rejectedCount: Int {
        blocks.filter { $0.failureReason != nil }.count
    }
    private var pendingCount: Int {
        blocks.count - appliedCount - rejectedCount
    }
    private var allResolved: Bool {
        pendingCount == 0
    }

    var body: some View {
        GlassCard(borderTint: DesignSystem.Colors.ai.opacity(0.4)) {
            summaryHeader
            if isExpanded {
                fileList
            }
            if !blocks.isEmpty && (appliedCount > 0 || rejectedCount > 0) {
                resultsStrip
            }
            buttonRow
        }
        .sheet(isPresented: $isReviewSheetPresented) {
            MultiFileDiffReviewSheet(
                blocks: blocks,
                onDismiss: { isReviewSheetPresented = false }
            )
        }
    }

    /// Inline result strip — shown when applyAllEdits has touched any block.
    /// Surfaces "Applied N · Rejected M · Pending P" so the user gets visible
    /// feedback (the Image #37 complaint: buttons appeared inert because
    /// nothing in the card changed after the click).
    private var resultsStrip: some View {
        HStack(spacing: DesignSystem.Spacing.standard) {
            if appliedCount > 0 {
                Label("\(appliedCount)", systemImage: "checkmark.circle.fill")
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(DesignSystem.Colors.success)
                    .monospacedDigit()
            }
            if rejectedCount > 0 {
                Label("\(rejectedCount)", systemImage: "xmark.circle.fill")
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(DesignSystem.Colors.destructive)
                    .monospacedDigit()
            }
            if pendingCount > 0 {
                Label("\(pendingCount)", systemImage: "circle.dashed")
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .monospacedDigit()
            }
            Spacer()
            if allResolved {
                Text(L10n("chat.multifileDiff.allResolved"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(DesignSystem.Colors.success)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.compact)
        .padding(.vertical, DesignSystem.Spacing.micro)
        .background(DesignSystem.Colors.glassSubtle)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous))
    }

    // MARK: - Subviews

    private var summaryHeader: some View {
        HStack(spacing: DesignSystem.Spacing.iconTextGap) {
            Image(systemName: "folder.fill")
                .font(DesignSystem.Typography.subtitle)
                .foregroundStyle(DesignSystem.Colors.ai)
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
            // Review all — opens a sheet rendering every block side-by-side
            // with its full diff. Also calls onReviewAll() so callers wanting
            // to override (e.g. open a custom viewer) can still hook in.
            Button(L10n("chat.multifileDiff.reviewAll")) {
                onReviewAll()
                isReviewSheetPresented = true
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

// MARK: - MultiFileDiffReviewSheet

/// Modal viewer that walks the user through each EditBlock with full diff
/// content + a status badge per file (pending / applied / rejected). The
/// "Review all" button on the summary card opened the void closure before —
/// now lands here.
private struct MultiFileDiffReviewSheet: View {

    let blocks: [EditBlock]
    let onDismiss: () -> Void

    @State private var selectedIndex: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DesignSystem.Colors.glassBorder)
            HSplitView {
                fileList
                    .frame(minWidth: 220, idealWidth: 260)
                diffPane
                    .frame(minWidth: 380)
            }
            Divider().overlay(DesignSystem.Colors.glassBorder)
            footer
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    private var header: some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundStyle(DesignSystem.Colors.ai)
            Text(L10n("chat.multifileDiff.review.title", "\(blocks.count)"))
                .font(DesignSystem.Typography.cardTitle)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(DesignSystem.Spacing.standard)
    }

    private var fileList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { idx, block in
                    Button {
                        selectedIndex = idx
                    } label: {
                        HStack {
                            statusGlyph(for: block)
                            Text(block.path)
                                .font(DesignSystem.Typography.monoSmall)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                        }
                        .padding(.horizontal, DesignSystem.Spacing.standard)
                        .padding(.vertical, DesignSystem.Spacing.compact)
                        .background(idx == selectedIndex
                                    ? DesignSystem.Colors.ai.opacity(0.18)
                                    : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, DesignSystem.Spacing.compact)
        }
        .background(DesignSystem.Colors.glassSubtle)
    }

    private var diffPane: some View {
        ScrollView {
            if blocks.indices.contains(selectedIndex) {
                let block = blocks[selectedIndex]
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.compact) {
                    Text(block.path)
                        .font(DesignSystem.Typography.monoLabelBold)
                    Text(block.search)
                        .font(DesignSystem.Typography.monoLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DesignSystem.Spacing.compact)
                        .background(DesignSystem.Colors.destructive.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous))
                    Text(block.replace)
                        .font(DesignSystem.Typography.monoLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DesignSystem.Spacing.compact)
                        .background(DesignSystem.Colors.success.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous))
                    if let reason = block.failureReason {
                        Text(reason)
                            .font(DesignSystem.Typography.label)
                            .foregroundStyle(DesignSystem.Colors.destructive)
                    }
                }
                .padding(DesignSystem.Spacing.standard)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(L10n("chat.multifileDiff.review.footer"))
                .font(DesignSystem.Typography.label)
                .foregroundStyle(.secondary)
            Spacer()
            Button(L10n("chat.multifileDiff.review.close")) { onDismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(DesignSystem.Spacing.standard)
    }

    @ViewBuilder
    private func statusGlyph(for block: EditBlock) -> some View {
        if block.appliedAt != nil {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(DesignSystem.Colors.success)
        } else if block.failureReason != nil {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(DesignSystem.Colors.destructive)
        } else {
            Image(systemName: "circle.dashed")
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
    }
}
