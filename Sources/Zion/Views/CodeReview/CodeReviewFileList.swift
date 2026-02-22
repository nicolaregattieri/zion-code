import SwiftUI

struct CodeReviewFileList: View {
    let files: [CodeReviewFile]
    @Binding var selectedID: UUID?
    var onReviewAll: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(L10n("codereview.files"))
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Button {
                    onReviewAll()
                } label: {
                    Label(L10n("codereview.reviewAll"), systemImage: "sparkles")
                        .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .padding(12)

            Divider()

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(files) { file in
                        fileRow(file)
                    }
                }
                .padding(8)
            }
        }
        .background(DesignSystem.Colors.glassSubtle)
    }

    private func fileRow(_ file: CodeReviewFile) -> some View {
        let isSelected = selectedID == file.id
        return Button {
            selectedID = file.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: file.status.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(file.status.color)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(URL(fileURLWithPath: file.path).lastPathComponent)
                        .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .monospaced))
                        .lineLimit(1)

                    Text(file.path)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                Spacer(minLength: 4)

                // Severity heatmap dot
                if !file.findings.isEmpty {
                    let worst = file.findings.contains { $0.severity == .critical } ? DesignSystem.Colors.destructive :
                               file.findings.contains { $0.severity == .warning } ? DesignSystem.Colors.warning : DesignSystem.Colors.info
                    Circle()
                        .fill(worst)
                        .frame(width: 6, height: 6)
                }

                // +/- count
                HStack(spacing: 2) {
                    Text("+\(file.additions)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.diffAddition)
                    Text("-\(file.deletions)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.diffDeletion)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius)
                    .fill(isSelected ? DesignSystem.Colors.selectionBackground : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
