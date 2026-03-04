import SwiftUI

struct CodeReviewSheet: View {
    @Bindable var model: RepositoryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var splitRatio: CGFloat = 0.25

    private var currentPRNumber: Int? {
        model.pullRequests.first(where: { $0.headBranch == model.branchReviewSource })?.number
    }

    var body: some View {
        VStack(spacing: 0) {
            CodeReviewStatsBar(stats: model.codeReviewStats, source: model.branchReviewSource, target: model.branchReviewTarget)

            Divider()

            DraggableSplitView(
                axis: .horizontal,
                ratio: $splitRatio,
                minLeading: DesignSystem.Layout.codeReviewFileListMinWidth,
                minTrailing: DesignSystem.Layout.codeReviewDiffMinWidth
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

                // Comment count badge
                if !model.prComments.isEmpty {
                    HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                        Image(systemName: "text.bubble.fill")
                            .font(DesignSystem.Typography.label)
                        Text("\(model.prComments.count)")
                            .font(DesignSystem.Typography.labelBold)
                    }
                    .foregroundStyle(DesignSystem.Colors.info)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DesignSystem.Colors.info.opacity(0.1))
                    .clipShape(Capsule())
                }

                Spacer()

                // Submit Review button (only when viewing a PR)
                if currentPRNumber != nil {
                    Button {
                        model.isPRReviewSubmitSheetVisible = true
                    } label: {
                        HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                            Image(systemName: "checkmark.message")
                            Text(L10n("pr.review.submit"))
                            if !model.pendingReviewComments.isEmpty {
                                Text("(\(model.pendingReviewComments.count))")
                                    .font(DesignSystem.Typography.metaBold)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(DesignSystem.Colors.codeReview)
                }

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
                .tint(DesignSystem.Colors.ai)
            }
            .padding(16)
        }
        .frame(minWidth: DesignSystem.Layout.codeReviewMinWidth, idealWidth: 1200, minHeight: DesignSystem.Layout.codeReviewMinHeight, idealHeight: 800)
        .sheet(isPresented: $model.isPRReviewSubmitSheetVisible) {
            PRReviewSubmitSheet(model: model)
        }
        .onAppear {
            guard model.codeReviewFiles.isEmpty else { return }
            model.ensureBranchReviewSelections()
            let source = model.branchReviewSource
            let target = model.branchReviewTarget
            if !source.isEmpty, !target.isEmpty {
                model.startCodeReview(source: source, target: target)
            }

            // Load PR comments if viewing a PR
            if let prNumber = currentPRNumber {
                model.loadPRComments(prNumber: prNumber)
            }
        }
    }
}
