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
                    .font(.system(size: 16, weight: .semibold))
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
                .tint(.orange)
                .disabled(model.reflogEntries.count < 2)

                Button(L10n("Fechar")) { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(16)

            Divider()

            // Timeline
            if model.reflogEntries.isEmpty {
                VStack(spacing: 12) {
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
                    .padding(12)
                }
            }
        }
        .frame(width: 700, height: 500)
    }

    private func reflogRow(_ entry: ReflogEntry, index: Int) -> some View {
        let isHovered = hoveredEntryID == entry.id
        let actionColor = colorForAction(entry.action)

        return HStack(spacing: 12) {
            // Timeline dot + line
            VStack(spacing: 0) {
                if index > 0 {
                    Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 2)
                }
                Circle()
                    .fill(actionColor)
                    .frame(width: 10, height: 10)
                if index < model.reflogEntries.count - 1 {
                    Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 2)
                }
            }
            .frame(width: 10)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    // Action badge
                    Text(entry.action)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(actionColor.opacity(0.15))
                        .foregroundStyle(actionColor)
                        .clipShape(Capsule())

                    Text(entry.shortHash)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(entry.relativeDate)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Text(entry.message)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? DesignSystem.Colors.glassHover : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
        case "commit": return .green
        case "pull": return .blue
        case "checkout": return .orange
        case "merge": return .purple
        case "rebase": return .pink
        case "reset": return .red
        case "cherry-pick": return .cyan
        case "clone": return .mint
        default: return .secondary
        }
    }
}
