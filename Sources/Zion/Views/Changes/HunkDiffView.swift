import SwiftUI

struct HunkDiffView: View {
    var model: RepositoryViewModel
    let file: String
    let hunks: [DiffHunk]
    @State private var collapsedHunks: Set<UUID> = []
    @State private var selectedLines: Set<UUID> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(hunks) { hunk in
                    hunkSection(hunk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DesignSystem.Colors.glassInset)
    }

    private func hunkSection(_ hunk: DiffHunk) -> some View {
        let isCollapsed = collapsedHunks.contains(hunk.id)

        return VStack(alignment: .leading, spacing: 0) {
            // Hunk header row
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                Button {
                    withAnimation(DesignSystem.Motion.snappy) {
                        if isCollapsed {
                            collapsedHunks.remove(hunk.id)
                        } else {
                            collapsedHunks.insert(hunk.id)
                        }
                    }
                } label: {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(DesignSystem.Typography.micro)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                }
                .buttonStyle(.plain)

                Text(hunk.header)
                    .font(DesignSystem.Typography.monoSmall)
                    .foregroundStyle(DesignSystem.Colors.diffHunkHeader)
                    .lineLimit(1)

                Spacer()

                // Stage hunk button
                Button {
                    model.stageHunk(hunk, file: file)
                } label: {
                    Label(L10n("Stage Hunk"), systemImage: "plus.circle")
                        .font(DesignSystem.Typography.label)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                // Stage selected lines button
                if !selectedLinesInHunk(hunk).isEmpty {
                    Button {
                        let sel = selectedLinesInHunk(hunk)
                        model.stageSelectedLines(from: hunk, selectedLineIDs: sel, file: file)
                        selectedLines.subtract(sel)
                    } label: {
                        Label(L10n("Stage Linhas"), systemImage: "text.badge.plus")
                            .font(DesignSystem.Typography.label)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(DesignSystem.Colors.success)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DesignSystem.Colors.diffHunkHeaderBg)

            if !isCollapsed {
                ForEach(hunk.lines) { line in
                    diffLineRow(line)
                }
            }
        }
    }

    private func selectedLinesInHunk(_ hunk: DiffHunk) -> Set<UUID> {
        let hunkLineIDs = Set(hunk.lines.filter { $0.type != .context }.map(\.id))
        return selectedLines.intersection(hunkLineIDs)
    }

    private func diffLineRow(_ line: DiffLine) -> some View {
        let isSelected = selectedLines.contains(line.id)
        let bgColor: Color
        let textColor: Color
        let prefix: String

        switch line.type {
        case .addition:
            bgColor = isSelected ? DesignSystem.Colors.diffAdditionBgSelected : DesignSystem.Colors.diffAdditionBg
            textColor = DesignSystem.Colors.diffAddition
            prefix = "+"
        case .deletion:
            bgColor = isSelected ? DesignSystem.Colors.diffDeletionBgSelected : DesignSystem.Colors.diffDeletionBg
            textColor = DesignSystem.Colors.diffDeletion
            prefix = "-"
        case .context:
            bgColor = Color.clear
            textColor = DesignSystem.Colors.diffContext
            prefix = " "
        }

        return HStack(spacing: 0) {
            // Line selection checkbox for changed lines
            if line.type != .context {
                Button {
                    if isSelected {
                        selectedLines.remove(line.id)
                    } else {
                        selectedLines.insert(line.id)
                    }
                } label: {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 20)
            } else {
                Spacer().frame(width: 20)
            }

            // Old line number
            Text(line.oldLineNumber.map { "\($0)" } ?? "")
                .font(DesignSystem.Typography.monoLabel)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 4)

            // New line number
            Text(line.newLineNumber.map { "\($0)" } ?? "")
                .font(DesignSystem.Typography.monoLabel)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 4)

            // Prefix (+/-/space)
            Text(prefix)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(textColor)
                .frame(width: 14)

            // Content
            Text(line.content)
                .font(DesignSystem.Typography.monoBody)
                .foregroundStyle(textColor)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bgColor)
        .contentShape(Rectangle())
    }
}
