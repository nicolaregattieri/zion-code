import SwiftUI

struct InteractiveRebaseSheet: View {
    @Bindable var model: RepositoryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draggedItem: RebaseItem?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            commitList
            Divider()
            footer
        }
        .frame(width: 700, height: 550)
    }

    private var header: some View {
        HStack {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.ai)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n("Rebase Interativo")).font(.headline)
                Text(L10n("Base: %@", model.rebaseBaseRef))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(L10n("%d commits", model.rebaseItems.count))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private var commitList: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(Array(model.rebaseItems.enumerated()), id: \.element.id) { index, item in
                    rebaseRow(item: item, index: index)
                }
            }
            .padding(12)
        }
    }

    private func rebaseRow(item: RebaseItem, index: Int) -> some View {
        HStack(spacing: 10) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 16)

            // Action picker
            Menu {
                ForEach(RebaseAction.allCases) { action in
                    Button {
                        model.rebaseItems[index].action = action
                    } label: {
                        Label(action.label, systemImage: action.icon)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: item.action.icon)
                        .font(.system(size: 10, weight: .bold))
                    Text(item.action.label)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(item.action.color.opacity(0.15))
                .foregroundStyle(item.action.color)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 90)

            // Hash
            Text(item.shortHash)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)

            // Subject
            Text(item.subject)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(item.action == .drop ? .secondary : .primary)
                .strikethrough(item.action == .drop)

            Spacer()

            // Quick action buttons
            HStack(spacing: 4) {
                Button {
                    if index > 0 {
                        model.rebaseItems.swapAt(index, index - 1)
                    }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(index == 0)

                Button {
                    if index < model.rebaseItems.count - 1 {
                        model.rebaseItems.swapAt(index, index + 1)
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(index == model.rebaseItems.count - 1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius)
                .fill(item.action == .drop ? DesignSystem.Colors.destructive.opacity(0.05) : DesignSystem.Colors.glassSubtle)
        )
    }

    private var footer: some View {
        HStack {
            // Legend
            HStack(spacing: 12) {
                ForEach(RebaseAction.allCases) { action in
                    HStack(spacing: 4) {
                        Circle().fill(action.color).frame(width: 6, height: 6)
                        Text(action.label)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Button(L10n("Cancelar")) { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.small)

            Button {
                model.executeInteractiveRebase()
            } label: {
                Label(L10n("Executar Rebase"), systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(DesignSystem.Colors.ai)
            .disabled(model.rebaseItems.isEmpty)
        }
        .padding(16)
    }
}
