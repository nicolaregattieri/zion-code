import SwiftUI

// MARK: - EditPreviewAction

enum EditPreviewAction: Equatable {
    case apply
    case reject
    case editRaw(String)
}

// MARK: - EditPreviewCard

struct EditPreviewCard: View {
    let block: EditBlock
    let isStreaming: Bool
    var onAction: (EditPreviewAction) -> Void

    @State private var isEditing: Bool = false
    @State private var draftXML: String = ""
    /// Optimistic per-card "we just clicked Apply, waiting for the
    /// service to flip block.appliedAt" flag. Resets whenever the
    /// authoritative block.appliedAt / failureReason settles. Without
    /// this the Apply button looked inert mid-async (file #54 report).
    @State private var pendingApply: Bool = false

    private var borderTint: Color {
        if block.appliedAt != nil { return DesignSystem.Colors.success.opacity(0.5) }
        if block.failureReason != nil { return DesignSystem.Colors.destructive.opacity(0.5) }
        return DesignSystem.Colors.ai.opacity(0.4)
    }

    var body: some View {
        GlassCard(borderTint: borderTint) {
            fileHeader
            Divider()
                .overlay(DesignSystem.Colors.glassBorderDark)
            diffSection
            if isEditing {
                editSection
            } else {
                footerButtons
            }
        }
        .onChange(of: block.appliedAt) { _, _ in pendingApply = false }
        .onChange(of: block.failureReason) { _, _ in pendingApply = false }
    }

    // MARK: - Subviews

    private var fileHeader: some View {
        HStack(spacing: DesignSystem.Spacing.iconTextGap) {
            Image(systemName: "doc.text")
                .font(DesignSystem.Typography.subtitle)
                .foregroundStyle(DesignSystem.Colors.ai)
            Text(block.path)
                .font(DesignSystem.Typography.monoSmall)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(L10n("chat.edit.preview.title"))
                .font(DesignSystem.Typography.labelBold)
                .foregroundStyle(DesignSystem.Colors.ai)
                .padding(.horizontal, DesignSystem.Spacing.compact)
                .padding(.vertical, DesignSystem.Spacing.micro)
                .background(DesignSystem.Colors.ai.opacity(0.15))
                .clipShape(Capsule())
        }
    }

    private var diffSection: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(searchLines.enumerated()), id: \.offset) { _, line in
                    DiffLineRow(prefix: "-", content: line, tint: DesignSystem.Colors.diffDeletionBg, textColor: DesignSystem.Colors.error)
                }
                ForEach(Array(replaceLines.enumerated()), id: \.offset) { _, line in
                    DiffLineRow(prefix: "+", content: line, tint: DesignSystem.Colors.diffAdditionBg, textColor: DesignSystem.Colors.success)
                }
            }
        }
        .frame(maxHeight: 220)
        .background(DesignSystem.Colors.glassInset)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous))
    }

    private var searchLines: [String] {
        block.search.components(separatedBy: "\n")
    }

    private var replaceLines: [String] {
        block.replace.components(separatedBy: "\n")
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
                Button(L10n("chat.edit.save")) {
                    saveTapped(draftXML)
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

    @ViewBuilder
    private var footerButtons: some View {
        if block.appliedAt != nil {
            appliedFooter
        } else if let reason = block.failureReason {
            rejectedFooter(reason: reason)
        } else {
            actionFooter
        }
    }

    private var appliedFooter: some View {
        HStack(spacing: DesignSystem.Spacing.iconTextGap) {
            Label(L10n("chat.editBlock.status.applied"), systemImage: "checkmark.circle.fill")
                .font(DesignSystem.Typography.bodySemibold)
                .foregroundStyle(DesignSystem.Colors.success)
            Spacer()
        }
        .padding(.horizontal, DesignSystem.Spacing.standard)
        .padding(.vertical, DesignSystem.Spacing.compact)
        .background(DesignSystem.Colors.success.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous))
    }

    private func rejectedFooter(reason: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.iconTextGap) {
            Label(reason == "rejected"
                ? L10n("chat.editBlock.status.rejected")
                : reason,
                  systemImage: "xmark.circle.fill")
                .font(DesignSystem.Typography.bodySemibold)
                .foregroundStyle(DesignSystem.Colors.destructive)
            Spacer()
        }
        .padding(.horizontal, DesignSystem.Spacing.standard)
        .padding(.vertical, DesignSystem.Spacing.compact)
        .background(DesignSystem.Colors.destructiveBg)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous))
    }

    private var actionFooter: some View {
        HStack(spacing: DesignSystem.Spacing.standard) {
            Button {
                applyTapped()
            } label: {
                HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                    if pendingApply {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(pendingApply
                        ? L10n("chat.edit.applying.label")
                        : L10n("chat.edit.apply"))
                }
            }
            .font(DesignSystem.Typography.bodySemibold)
            .foregroundStyle(applyForeground)
            .buttonStyle(.plain)
            .padding(.horizontal, DesignSystem.Spacing.standard)
            .padding(.vertical, DesignSystem.Spacing.compact)
            .background(applyBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous))
            .disabled(isStreaming || pendingApply)

            Button(L10n("chat.edit.reject")) {
                rejectTapped()
            }
            .font(DesignSystem.Typography.body)
            .foregroundStyle(DesignSystem.Colors.destructive)
            .buttonStyle(.plain)
            .padding(.horizontal, DesignSystem.Spacing.standard)
            .padding(.vertical, DesignSystem.Spacing.compact)
            .background(DesignSystem.Colors.destructiveBg)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous))
            .disabled(pendingApply)

            Spacer()

            Button(L10n("chat.edit.editRaw")) {
                editTapped()
            }
            .font(DesignSystem.Typography.body)
            .foregroundStyle(DesignSystem.Colors.textSecondary)
            .buttonStyle(.plain)
            .disabled(pendingApply)
        }
    }

    private var applyForeground: Color {
        if isStreaming || pendingApply { return DesignSystem.Colors.textTertiary }
        return DesignSystem.Colors.success
    }

    private var applyBackground: Color {
        if isStreaming { return DesignSystem.Colors.glassSubtle }
        if pendingApply { return DesignSystem.Colors.ai.opacity(0.15) }
        return DesignSystem.Colors.success.opacity(0.15)
    }

    // MARK: - Action Helpers (testable)

    internal func applyTapped() {
        guard !isStreaming, !pendingApply else { return }
        pendingApply = true
        onAction(.apply)
    }

    internal func rejectTapped() {
        onAction(.reject)
    }

    internal func editTapped() {
        draftXML = block.search + "\n=======\n" + block.replace
        isEditing = true
    }

    internal func saveTapped(_ xml: String) {
        onAction(.editRaw(xml))
        isEditing = false
    }
}

// MARK: - DiffLineRow

private struct DiffLineRow: View {
    let prefix: String
    let content: String
    let tint: Color
    let textColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.compact) {
            Text(prefix)
                .font(DesignSystem.Typography.monoSmall)
                .foregroundStyle(textColor)
                .frame(width: 12, alignment: .center)
            Text(content)
                .font(DesignSystem.Typography.monoSmall)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DesignSystem.Spacing.compact)
        .padding(.vertical, DesignSystem.Spacing.micro)
        .background(tint)
    }
}
