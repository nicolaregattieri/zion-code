import SwiftUI

struct FileHistorySheet: View {
    var model: RepositoryViewModel
    let fileName: String
    @Environment(\.dismiss) private var dismiss
    @State private var hoveredID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if model.isFileHistoryLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(L10n("filehistory.loading"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.fileHistoryEntries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text(L10n("filehistory.empty"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.fileHistoryEntries) { entry in
                            entryRow(entry)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(width: 560, height: 460)
    }

    private var header: some View {
        HStack(spacing: DesignSystem.Spacing.toolbarItemGap) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title3)
                .foregroundStyle(DesignSystem.Colors.info)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n("filehistory.title"))
                    .font(.headline)
                Text(fileName)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("\(model.fileHistoryEntries.count) commits")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(16)
    }

    private func entryRow(_ entry: FileHistoryEntry) -> some View {
        let isHovered = hoveredID == entry.id
        return HStack(spacing: DesignSystem.Spacing.toolbarItemGap) {
            Text(entry.shortHash)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(DesignSystem.Colors.info)
                .frame(width: 60, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.message)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)
                HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                    Text(entry.author)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(entry.date)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if isHovered {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.hash, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L10n("Copiar Hash"))

                Button {
                    model.selectCommit(entry.hash)
                    model.navigateToGraphRequested = true
                    dismiss()
                } label: {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignSystem.Colors.info)
                }
                .buttonStyle(.plain)
                .help(L10n("filehistory.showInGraph"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isHovered ? DesignSystem.Colors.glassHover : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
        .contentShape(Rectangle())
        .onHover { h in hoveredID = h ? entry.id : nil }
    }
}
