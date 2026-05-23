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

    var body: some View {
        GlassCard(borderTint: DesignSystem.Colors.ai.opacity(0.4)) {
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

    private var footerButtons: some View {
        HStack(spacing: DesignSystem.Spacing.standard) {
            Button(L10n("chat.edit.apply")) {
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

            Spacer()

            Button(L10n("chat.edit.editRaw")) {
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
