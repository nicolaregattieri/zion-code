import SwiftUI

struct BlameEntry: Identifiable {
    let id = UUID()
    let commitHash: String
    let shortHash: String
    let author: String
    let date: Date
    let lineNumber: Int
    let content: String
}

struct BlameView: View {
    let entries: [BlameEntry]
    let fileName: String
    var model: RepositoryViewModel
    var onCommitTapped: ((String) -> Void)?
    @State private var hoveredEntryID: UUID?
    @State private var explanationEntryID: UUID?

    // Color mapping: assign consistent colors to authors
    private var authorColors: [String: Color] {
        let palette: [Color] = [
            .blue, .green, .orange, .purple, .pink, .cyan, .mint, .indigo, .teal, .yellow
        ]
        var map: [String: Color] = [:]
        var idx = 0
        for entry in entries {
            if map[entry.author] == nil {
                map[entry.author] = palette[idx % palette.count]
                idx += 1
            }
        }
        return map
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(entries) { entry in
                    blameRow(entry)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func blameRow(_ entry: BlameEntry) -> some View {
        let isHovered = hoveredEntryID == entry.id
        let color = authorColors[entry.author] ?? .secondary

        return HStack(spacing: 0) {
            // Blame gutter
            HStack(spacing: 6) {
                // Color bar for author
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.shortHash)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(color)
                    Text(entry.author.components(separatedBy: " ").first ?? entry.author)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isHovered && model.isAIConfigured {
                    Button {
                        model.explainBlameEntry(entry: entry, fileName: fileName)
                        explanationEntryID = entry.id
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.system(size: 8))
                            .foregroundStyle(DesignSystem.Colors.semanticSearch)
                    }
                    .buttonStyle(.plain)
                    .help(L10n("Explicar com IA"))
                    .popover(isPresented: Binding(
                        get: { explanationEntryID == entry.id && model.aiBlameEntryID == entry.id && !model.aiBlameExplanation.isEmpty },
                        set: { if !$0 { explanationEntryID = nil; model.aiBlameEntryID = nil } }
                    )) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles").font(.system(size: 10)).foregroundStyle(DesignSystem.Colors.semanticSearch)
                                Text(entry.shortHash).font(.system(size: 10, weight: .bold, design: .monospaced))
                            }
                            Text(model.aiBlameExplanation)
                                .font(.system(size: 11))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: 300)
                    }
                } else {
                    Text(relativeDate(entry.date))
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 160)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isHovered ? DesignSystem.Colors.glassHover : DesignSystem.Colors.glassSubtle)
            .contentShape(Rectangle())
            .onTapGesture {
                onCommitTapped?(entry.commitHash)
            }
            .onHover { h in hoveredEntryID = h ? entry.id : nil }

            // Line number
            Text("\(entry.lineNumber)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.4))
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 6)

            // Code content
            Text(entry.content)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .foregroundStyle(.primary.opacity(0.85))

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func relativeDate(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 3600 { return "\(max(1, seconds / 60))m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        let days = seconds / 86400
        if days < 30 { return "\(days)d" }
        if days < 365 { return "\(days / 30)mo" }
        return "\(days / 365)y"
    }
}
