import SwiftUI

struct ReflogSheet: View {
    var model: RepositoryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var hoveredEntryID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(DesignSystem.IconSize.sectionHeader)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n("Reflog")).font(.headline)
                    Text(L10n("Historico de acoes do repositorio"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()

                Button {
                    model.undoLastAction()
                    dismiss()
                } label: {
                    Label(L10n("Desfazer Ultima Acao"), systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(DesignSystem.Colors.warning)
                .disabled(model.reflogEntries.count < 2)
                .help(L10n("Voltar ao estado anterior (git reset --soft)"))

                Button(L10n("Fechar")) { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(DesignSystem.Spacing.screenEdge - 8)

            Divider()

            // Timeline
            if model.reflogEntries.isEmpty {
                VStack(spacing: DesignSystem.Spacing.cardPadding) {
                    ProgressView()
                    Text(L10n("Carregando reflog..."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.reflogEntries.enumerated()), id: \.element.id) { index, entry in
                            reflogRow(entry, index: index)
                        }
                    }
                    .padding(DesignSystem.Spacing.cardPadding)
                }
            }
        }
        .frame(width: 700, height: 500)
    }

    private func reflogRow(_ entry: ReflogEntry, index: Int) -> some View {
        let isHovered = hoveredEntryID == entry.id
        let actionColor = colorForAction(entry.action)

        return HStack(spacing: DesignSystem.Spacing.cardPadding) {
            // Timeline dot + line
            VStack(spacing: 0) {
                if index > 0 {
                    Rectangle().fill(DesignSystem.Colors.glassStroke).frame(width: 2)
                }
                Circle()
                    .fill(actionColor)
                    .frame(width: 10, height: 10)
                if index < model.reflogEntries.count - 1 {
                    Rectangle().fill(DesignSystem.Colors.glassStroke).frame(width: 2)
                }
            }
            .frame(width: 10)

            // Content
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.micro) {
                HStack(spacing: DesignSystem.Spacing.standard) {
                    // Action badge
                    Text(entry.action)
                        .font(DesignSystem.Typography.monoLabelBold)
                        .padding(.horizontal, DesignSystem.Spacing.compact)
                        .padding(.vertical, 2)
                        .background(actionColor.opacity(0.15))
                        .foregroundStyle(actionColor)
                        .clipShape(Capsule())
                        .help(ReflogEntry.tooltip(for: entry.action) ?? "")

                    Text(entry.shortHash)
                        .font(DesignSystem.Typography.monoSmall)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(entry.relativeDate)
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.tertiary)
                }

                Text(entry.detail)
                    .font(DesignSystem.Typography.body)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                if !entry.branch.isEmpty, entry.action.lowercased() != "checkout" {
                    Text(L10n("na branch %@", entry.branch))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(DesignSystem.Spacing.standard + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? DesignSystem.Colors.glassHover : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius))
            .contentShape(Rectangle())
            .onHover { h in hoveredEntryID = h ? entry.id : nil }
            .contextMenu {
                Button {
                    model.resetToCommit(entry.hash, hard: false)
                    dismiss()
                } label: {
                    Label(L10n("Reset --soft para aqui"), systemImage: "arrow.uturn.backward")
                }
                Button(role: .destructive) {
                    model.resetToCommit(entry.hash, hard: true)
                    dismiss()
                } label: {
                    Label(L10n("Reset --hard para aqui"), systemImage: "exclamationmark.triangle")
                }
                Divider()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.hash, forType: .string)
                } label: {
                    Label(L10n("Copiar Hash"), systemImage: "doc.on.doc")
                }
            }
        }
    }

    private func colorForAction(_ action: String) -> Color {
        switch action.lowercased() {
        case "commit", "commit (initial)": return DesignSystem.Colors.success
        case "commit (amend)": return DesignSystem.Colors.warning
        case "pull": return DesignSystem.Colors.info
        case "checkout": return DesignSystem.Colors.warning
        case "merge": return DesignSystem.Colors.ai
        case "rebase": return DesignSystem.Colors.destructive
        case "reset": return DesignSystem.Colors.destructive
        case "cherry-pick": return DesignSystem.Colors.commitSplit
        case "clone": return DesignSystem.Colors.commitSplit
        default: return .secondary
        }
    }
}
