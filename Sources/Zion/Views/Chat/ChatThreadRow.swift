import SwiftUI

// MARK: - ChatThreadRow

struct ChatThreadRow: View {

    let thread: ChatThread
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onRename: (String) -> Void

    @State private var isRenaming: Bool = false
    @State private var draftTitle: String = ""
    @State private var isHovered: Bool = false
    @State private var showDeleteAlert: Bool = false

    // MARK: - Body

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
            rowContent
            Spacer(minLength: 0)
            if isHovered && !isRenaming {
                trashButton
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.standard)
        .padding(.vertical, DesignSystem.Spacing.compact)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) {
            startRenaming()
        }
        .onTapGesture(count: 1) {
            if !isRenaming {
                onSelect()
            }
        }
        .contextMenu {
            Button(L10n("chat.thread.rename")) { startRenaming() }
            Divider()
            Button(L10n("chat.thread.delete"), role: .destructive) { showDeleteAlert = true }
        }
        .alert(L10n("chat.thread.confirmDelete"), isPresented: $showDeleteAlert) {
            Button(L10n("chat.thread.delete"), role: .destructive) { onDelete() }
            Button(L10n("Cancelar"), role: .cancel) {}
        }
    }

    // MARK: - Row Content

    @ViewBuilder
    private var rowContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.micro) {
            if isRenaming {
                TextField("", text: $draftTitle)
                    .chatScaledFont(role: .label)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        commitRename()
                    }
                    .onExitCommand {
                        cancelRename()
                    }
            } else {
                Text(thread.title)
                    .chatScaledFont(role: .label)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Text(relativeDate)
                .chatScaledFont(role: .label, design: .monospaced)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
    }

    // MARK: - Trash Button

    private var trashButton: some View {
        Button {
            showDeleteAlert = true
        } label: {
            Image(systemName: "trash")
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.destructive)
                .frame(width: DesignSystem.Spacing.cardPadding, height: DesignSystem.Spacing.cardPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isHovered ? DesignSystem.Opacity.visible : 0)
    }

    // MARK: - Background

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius)
                .fill(DesignSystem.Colors.selectionBackground)
        } else if isHovered {
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius)
                .fill(DesignSystem.Colors.glassHover)
        } else {
            Color.clear
        }
    }

    // MARK: - Helpers

    private var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let date = thread.messages.last?.timestamp ?? thread.createdAt
        return String(format: L10n("chat.thread.lastUpdatedAt"), formatter.localizedString(for: date, relativeTo: Date()))
    }

    private func startRenaming() {
        draftTitle = thread.title
        isRenaming = true
    }

    private func commitRename() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onRename(trimmed)
        }
        isRenaming = false
    }

    private func cancelRename() {
        isRenaming = false
    }
}
