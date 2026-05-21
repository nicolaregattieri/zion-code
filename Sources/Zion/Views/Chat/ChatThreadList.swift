import SwiftUI

// MARK: - ChatThreadList

struct ChatThreadList: View {

    let threads: [ChatThread]
    let activeThreadID: UUID
    let onSelect: (UUID) -> Void
    let onNew: () -> Void
    let onDelete: (UUID) -> Void
    let onRename: (UUID, String) -> Void
    @Binding var isCollapsed: Bool

    // MARK: - Constants

    private static let expandedWidth: CGFloat = 200

    // MARK: - Body

    var body: some View {
        if isCollapsed {
            collapsedToggleButton
        } else {
            VStack(spacing: 0) {
                header
                Divider()
                    .background(DesignSystem.Colors.glassBorder)
                listContent
            }
            .frame(width: Self.expandedWidth)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
            Button {
                onNew()
            } label: {
                HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                    Image(systemName: "plus")
                        .font(DesignSystem.Typography.label)
                    Text(L10n("chat.thread.new"))
                        .font(DesignSystem.Typography.labelMedium)
                }
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            collapseButton
        }
        .padding(.horizontal, DesignSystem.Spacing.standard)
        .padding(.vertical, DesignSystem.Spacing.compact)
    }

    // MARK: - List Content

    @ViewBuilder
    private var listContent: some View {
        if threads.isEmpty {
            emptyState
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: DesignSystem.Spacing.micro) {
                    ForEach(threads) { thread in
                        ChatThreadRow(
                            thread: thread,
                            isSelected: thread.id == activeThreadID,
                            onSelect: { onSelect(thread.id) },
                            onDelete: { onDelete(thread.id) },
                            onRename: { newTitle in onRename(thread.id, newTitle) }
                        )
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.micro)
                .padding(.vertical, DesignSystem.Spacing.micro)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack {
            Spacer()
            Text(L10n("chat.thread.empty"))
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.cardPadding)
    }

    // MARK: - Collapse Button

    private var collapseButton: some View {
        Button {
            isCollapsed = true
        } label: {
            Image(systemName: "sidebar.left")
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(width: DesignSystem.Spacing.cardPadding, height: DesignSystem.Spacing.cardPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n("chat.thread.sidebar.toggle"))
    }

    // MARK: - Collapsed Toggle Button

    private var collapsedToggleButton: some View {
        Button {
            isCollapsed = false
        } label: {
            Image(systemName: "sidebar.left")
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(width: DesignSystem.Spacing.cardPadding, height: DesignSystem.Spacing.cardPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n("chat.thread.sidebar.toggle"))
        .padding(DesignSystem.Spacing.standard)
    }
}
