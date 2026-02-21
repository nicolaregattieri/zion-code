import SwiftUI

struct CodeReviewDiffPane: View {
    var model: RepositoryViewModel
    let file: CodeReviewFile?

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
                        Text("+\(file.additions)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.green)
                        Text("-\(file.deletions)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.red)
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
                        ReviewFindingsView(findings: file.findings, tintColor: .indigo)
                            .padding(.horizontal, 12)
                    }

                    // Diff hunks
                    if !file.hunks.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(file.hunks) { hunk in
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(hunk.header)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.blue.opacity(0.8))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.blue.opacity(0.05))

                                    ForEach(hunk.lines) { line in
                                        diffLineView(line)
                                    }
                                }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(DesignSystem.Colors.glassHover, lineWidth: 1))
                        .padding(.horizontal, 12)
                    } else if !file.diff.isEmpty {
                        // Raw diff fallback
                        Text(file.diff)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DesignSystem.Colors.glassSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
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

    private func diffLineView(_ line: DiffLine) -> some View {
        let bg: Color
        let fg: Color
        switch line.type {
        case .addition:
            bg = Color.green.opacity(0.12)
            fg = .green
        case .deletion:
            bg = Color.red.opacity(0.12)
            fg = .red
        case .context:
            bg = .clear
            fg = .primary.opacity(0.7)
        }

        return HStack(spacing: 0) {
            // Line numbers
            HStack(spacing: 2) {
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
    }
}
