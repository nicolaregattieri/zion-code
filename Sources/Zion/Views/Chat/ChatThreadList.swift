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

    private static let expandedWidth: CGFloat = 260

    // MARK: - Body

    var body: some View {
        if isCollapsed {
            EmptyView()
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
        Button {
            onNew()
        } label: {
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                Image(systemName: "square.and.pencil")
                    .font(DesignSystem.Typography.body)
                Text(L10n("chat.thread.new"))
                    .font(DesignSystem.Typography.bodySemibold)
                Spacer()
            }
            .foregroundStyle(DesignSystem.Colors.textPrimary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DesignSystem.Spacing.cardPadding)
        .padding(.top, DesignSystem.Spacing.sectionGap)
        .padding(.bottom, DesignSystem.Spacing.standard)
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

}
