import SwiftUI

struct CodeReviewDiffPane: View {
    var model: RepositoryViewModel
    let file: CodeReviewFile?
    @State private var activeCommentLine: Int?

    var body: some View {
        if let file {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // File header
                    HStack {
                        Image(systemName: file.status.icon)
                            .foregroundStyle(file.status.color)
                        Text(file.path)
                            .font(.system(.subheadline, design: .monospaced))
                            .fontWeight(.bold)
                        Spacer()
                        if !file.inlineComments.isEmpty {
                            HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                                Image(systemName: "text.bubble")
                                    .font(.system(size: 10))
                                Text("\(file.inlineComments.count)")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundStyle(DesignSystem.Colors.info)
                        }
                        Text("+\(file.additions)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.diffAddition)
                        Text("-\(file.deletions)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.diffDeletion)
                    }
                    .padding(12)

                    // AI Explanation
                    if let explanation = file.explanation {
                        DiffExplanationCard(explanation: explanation)
                            .padding(.horizontal, 12)
                    } else if model.isCodeReviewLoading {
                        DiffExplanationShimmer()
                            .padding(.horizontal, 12)
                    }

                    // Findings
                    if !file.findings.isEmpty {
                        ReviewFindingsView(
                            findings: file.findings,
                            tintColor: DesignSystem.Colors.codeReview,
                            onOpenFile: { _, snippet in
                                model.openFileInEditor(relativePath: file.path, highlightQuery: snippet)
                            }
                        )
                            .padding(.horizontal, 12)
                    }

                    // Diff hunks with inline comments
                    if !file.hunks.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(file.hunks) { hunk in
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(hunk.header)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(DesignSystem.Colors.diffHunkHeader)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(DesignSystem.Colors.diffHunkHeaderBgLight)

                                    ForEach(hunk.lines) { line in
                                        diffLineView(line, file: file)
                                    }
                                }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius))
                        .overlay(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius).stroke(DesignSystem.Colors.glassHover, lineWidth: 1))
                        .padding(.horizontal, 12)
                    } else if !file.diff.isEmpty {
                        // Raw diff fallback
                        Text(file.diff)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DesignSystem.Colors.glassSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius))
                            .padding(.horizontal, 12)
                    }
                }
                .padding(.bottom, 16)
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text(L10n("codereview.selectFile"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func diffLineView(_ line: DiffLine, file: CodeReviewFile) -> some View {
        let bg: Color = {
            switch line.type {
            case .addition: return DesignSystem.Colors.diffAdditionBg
            case .deletion: return DesignSystem.Colors.diffDeletionBg
            case .context: return .clear
            }
        }()
        let fg: Color = {
            switch line.type {
            case .addition: return DesignSystem.Colors.diffAddition
            case .deletion: return DesignSystem.Colors.diffDeletion
            case .context: return DesignSystem.Colors.diffContext
            }
        }()

        let lineNumber = line.newLineNumber ?? line.oldLineNumber
        let commentsForLine = file.inlineComments.filter { $0.line == lineNumber }

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                // Add comment button (hover gutter)
                addCommentGutter(line: line)

                // Line numbers
                HStack(spacing: DesignSystem.Spacing.iconGroupedGap) {
                    Text(line.oldLineNumber.map { String($0) } ?? "")
                        .frame(width: 36, alignment: .trailing)
                    Text(line.newLineNumber.map { String($0) } ?? "")
                        .frame(width: 36, alignment: .trailing)
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.trailing, 8)

                Text(line.content)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(fg)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 1)
            .background(bg)

            // Inline comments
            if !commentsForLine.isEmpty {
                PRCommentThread(comments: commentsForLine) { replyBody in
                    if let ln = lineNumber {
                        model.postPRComment(
                            prNumber: currentPRNumber ?? 0,
                            body: replyBody,
                            path: file.path,
                            line: ln
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }

            // Inline comment input
            if activeCommentLine == lineNumber, let ln = lineNumber {
                PRInlineCommentInput(
                    path: file.path,
                    line: ln,
                    onPost: { body in
                        model.postPRComment(
                            prNumber: currentPRNumber ?? 0,
                            body: body,
                            path: file.path,
                            line: ln
                        )
                        activeCommentLine = nil
                    },
                    onCancel: {
                        activeCommentLine = nil
                    }
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func addCommentGutter(line: DiffLine) -> some View {
        let lineNumber = line.newLineNumber ?? line.oldLineNumber
        if lineNumber != nil, currentPRNumber != nil {
            Button {
                activeCommentLine = lineNumber
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.info)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(0.4)
        } else {
            Color.clear.frame(width: 16)
        }
    }

    /// Resolve the current PR number from the review context.
    private var currentPRNumber: Int? {
        model.pullRequests.first(where: { $0.headBranch == model.branchReviewSource })?.number
    }
}
