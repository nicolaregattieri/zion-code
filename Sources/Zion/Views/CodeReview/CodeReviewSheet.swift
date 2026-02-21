import SwiftUI

struct CodeReviewSheet: View {
    @Bindable var model: RepositoryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var splitRatio: CGFloat = 0.25

    var body: some View {
        VStack(spacing: 0) {
            CodeReviewStatsBar(stats: model.codeReviewStats, source: model.branchReviewSource, target: model.branchReviewTarget)

            Divider()

            DraggableSplitView(
                axis: .horizontal,
                ratio: $splitRatio,
                minLeading: 220,
                minTrailing: 600
            ) {
                CodeReviewFileList(
                    files: model.codeReviewFiles,
                    selectedID: $model.selectedReviewFileID,
                    onReviewAll: { model.reviewAllCodeReviewFiles() }
                )
            } trailing: {
                CodeReviewDiffPane(
                    model: model,
                    file: model.codeReviewFiles.first { $0.id == model.selectedReviewFileID }
                )
            }

            Divider()

            // Footer
            HStack {
                Button(L10n("Fechar")) { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button {
                    model.copyCodeReviewSummary()
                } label: {
                    Label(L10n("codereview.copySummary"), systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Button {
                    model.exportCodeReviewMarkdown()
                } label: {
                    Label(L10n("codereview.exportMarkdown"), systemImage: "arrow.down.doc")
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
            }
            .padding(16)
        }
        .frame(minWidth: 1000, idealWidth: 1200, minHeight: 700, idealHeight: 800)
    }
}
