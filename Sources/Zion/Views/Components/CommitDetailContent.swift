import SwiftUI

struct CommitDetailContent: View {
    let rawDetails: String
    var model: RepositoryViewModel?
    var commitID: String?
    @State private var expandedFile: String?

    private var parsed: ParsedDetail { ParsedDetail(rawDetails) }

    var body: some View {
        let detail = parsed

        if model?.isAIConfigured == true, model?.selectedCommitDetailTab == .aiReview, let model, let commitID {
            aiReviewContent(model: model, commitID: commitID)
        } else if detail.isPlaceholder {
            VStack(spacing: 16) {
                Image(systemName: "arrow.left.circle")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                Text(rawDetails)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 40)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                // Commit message
                if !detail.subject.isEmpty {
                    Text(detail.subject)
                        .font(.system(size: 14, weight: .bold))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !detail.body.isEmpty {
                    Text(detail.body)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Metadata grid
                VStack(alignment: .leading, spacing: 8) {
                    if !detail.commitHash.isEmpty {
                        metadataRow(label: L10n("Commit"), value: detail.commitHash, mono: true)
                    }
                    if !detail.mergeInfo.isEmpty {
                        metadataRow(label: L10n("Merge"), value: detail.mergeInfo, mono: true)
                    }
                    if !detail.author.isEmpty {
                        metadataRow(label: L10n("Author"), value: detail.author)
                    }
                    if !detail.authorDate.isEmpty {
                        metadataRow(label: L10n("Date"), value: detail.authorDate)
                    }
                    if !detail.committer.isEmpty && detail.committer != detail.author {
                        metadataRow(label: L10n("Committer"), value: detail.committer)
                    }
                    if !detail.commitDate.isEmpty && detail.commitDate != detail.authorDate {
                        metadataRow(label: L10n("Commit Date"), value: detail.commitDate)
                    }
                }
                .padding(10)
                .background(DesignSystem.Colors.glassSubtle)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius))

                // Changed files
                if !detail.changedFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(L10n("Arquivos alterados"))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(detail.changedFiles.count)")
                                .font(DesignSystem.Typography.monoLabelBold)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(detail.changedFiles.enumerated()), id: \.offset) { _, file in
                                VStack(alignment: .leading, spacing: 0) {
                                    Button {
                                        if expandedFile == file.path {
                                            expandedFile = nil
                                        } else {
                                            expandedFile = file.path
                                            if let model, let commitID {
                                                model.loadDiffForCommitFile(commitID: commitID, file: file.path)
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                                            fileStatusBadge(file.status)
                                            Text(file.path)
                                                .font(DesignSystem.Typography.monoSmall)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            Spacer()
                                            if let model {
                                                Button {
                                                    model.openFileInEditor(relativePath: file.path)
                                                } label: {
                                                    Image(systemName: "pencil.and.outline")
                                                        .font(DesignSystem.Typography.metaBold)
                                                        .foregroundStyle(.secondary)
                                                }
                                                .buttonStyle(.plain)
                                                .cursorArrow()
                                                .help(L10n("Abrir no Editor"))
                                            }
                                            if model != nil && commitID != nil {
                                                Image(systemName: expandedFile == file.path ? "chevron.down" : "chevron.right")
                                                    .font(DesignSystem.Typography.micro)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .contextMenu {
                                        if let model {
                                            Button {
                                                model.openFileInEditor(relativePath: file.path)
                                            } label: {
                                                Label(L10n("Abrir no Editor"), systemImage: "pencil.and.outline")
                                            }
                                        }
                                    }

                                    if expandedFile == file.path, let model {
                                        if model.isAIConfigured {
                                            HStack {
                                                Button {
                                                    model.explainDiffDetailed(fileName: file.path, diff: model.currentCommitFileDiff)
                                                } label: {
                                                    if model.isExplainingDiff {
                                                        ProgressView().controlSize(.small).frame(width: 12, height: 12)
                                                    } else {
                                                        Label(L10n("diff.explanation.title"), systemImage: "sparkles")
                                                    }
                                                }
                                                .buttonStyle(.bordered).controlSize(.mini)
                                                .disabled(model.isExplainingDiff || model.currentCommitFileDiff.isEmpty)
                                                .help(L10n("Explicar diff com IA"))
                                                Spacer()
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                        }

                                        if let explanation = model.currentDiffExplanation {
                                            DiffExplanationCard(explanation: explanation) {
                                                model.currentDiffExplanation = nil
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.bottom, 4)
                                        } else if model.isExplainingDiff {
                                            DiffExplanationShimmer()
                                                .padding(.horizontal, 8)
                                                .padding(.bottom, 4)
                                        }

                                        if !model.currentCommitFileDiffHunks.isEmpty {
                                            HunkDiffView(model: model, file: file.path, hunks: model.currentCommitFileDiffHunks)
                                                .frame(maxHeight: 300)
                                        }
                                    }
                                }
                            }
                        }
                        .background(DesignSystem.Colors.glassOverlay)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: commitID) { _, _ in
                expandedFile = nil
            }
        }
    }

    @ViewBuilder
    private func aiReviewContent(model: RepositoryViewModel, commitID: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.ai)
                Text(L10n("graph.commit.review.tab.ai"))
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Button {
                    model.reviewCommitChanges(commitID: commitID)
                } label: {
                    if model.reviewingCommitID == commitID {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(DesignSystem.Typography.labelBold)
                    }
                }
                .buttonStyle(.plain)
                .cursorArrow()
                .foregroundStyle(.secondary)
                .help(L10n("graph.commit.review"))
                .accessibilityLabel(L10n("graph.commit.review"))
            }

            if model.reviewingCommitID == commitID {
                HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n("graph.commit.review.loading"))
                        .font(DesignSystem.Typography.bodySmall)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if let findings = model.cachedReviewFindings(for: commitID) {
                ReviewFindingsView(
                    findings: findings,
                    onOpenFile: { file, snippet in
                        model.openFileInEditor(relativePath: file, highlightQuery: snippet)
                    },
                    onDismiss: nil
                )
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text(L10n("graph.commit.review.empty"))
                        .font(DesignSystem.Typography.bodySmall)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        model.reviewCommitChanges(commitID: commitID)
                    } label: {
                        Label(L10n("graph.commit.review"), systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(DesignSystem.Colors.ai)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
    }

    private func metadataRow(label: String, value: String, mono: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(DesignSystem.Typography.labelBold)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.system(size: 11, weight: .regular, design: mono ? .monospaced : .default))
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private func fileStatusBadge(_ status: String) -> some View {
        let (color, icon): (Color, String) = {
            switch status.uppercased() {
            case "M", "MM": return (DesignSystem.Colors.fileModified, "pencil")
            case "A": return (DesignSystem.Colors.fileAdded, "plus")
            case "D": return (DesignSystem.Colors.fileDeleted, "minus")
            case "R": return (DesignSystem.Colors.fileRenamed, "arrow.right")
            case "C": return (DesignSystem.Colors.ai, "doc.on.doc")
            default: return (.secondary, "questionmark")
            }
        }()

        Image(systemName: icon)
            .font(DesignSystem.Typography.metaBold)
            .foregroundStyle(color)
            .frame(width: 18, height: 18)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.microCornerRadius))
    }
}

private struct ChangedFile {
    let status: String
    let path: String
}

private struct ParsedDetail {
    let isPlaceholder: Bool
    let commitHash: String
    let mergeInfo: String
    let author: String
    let authorDate: String
    let committer: String
    let commitDate: String
    let subject: String
    let body: String
    let changedFiles: [ChangedFile]

    init(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Detect placeholder/loading states
        if trimmed.isEmpty || !trimmed.contains("commit ") || trimmed.count < 20 {
            isPlaceholder = true
            commitHash = ""; mergeInfo = ""; author = ""; authorDate = ""
            committer = ""; commitDate = ""; subject = ""; body = ""
            changedFiles = []
            return
        }

        isPlaceholder = false
        let lines = trimmed.components(separatedBy: "\n")

        var hash = ""
        var merge = ""
        var auth = ""
        var authDate = ""
        var comm = ""
        var commDate = ""
        var messageLines: [String] = []
        var files: [ChangedFile] = []
        var inMessage = false
        var pastHeaders = false

        for line in lines {
            if !pastHeaders {
                if line.hasPrefix("commit ") {
                    hash = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("Merge:") {
                    merge = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("Author:") {
                    auth = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("AuthorDate:") {
                    authDate = String(line.dropFirst(11)).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("Commit:") {
                    comm = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("CommitDate:") {
                    commDate = String(line.dropFirst(11)).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("Date:") {
                    authDate = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                } else if line.trimmingCharacters(in: .whitespaces).isEmpty && !hash.isEmpty {
                    pastHeaders = true
                    inMessage = true
                }
            } else if inMessage {
                let stripped = line.hasPrefix("    ") ? String(line.dropFirst(4)) : line
                // Detect file status lines (single letter + tab + path)
                if Self.isFileStatusLine(line) {
                    inMessage = false
                    if let file = Self.parseFileLine(line) {
                        files.append(file)
                    }
                } else if line.trimmingCharacters(in: .whitespaces).isEmpty && !messageLines.isEmpty {
                    // Could be end of message or blank line in message
                    messageLines.append("")
                } else {
                    messageLines.append(stripped)
                }
            } else {
                // File status section
                if let file = Self.parseFileLine(line) {
                    files.append(file)
                }
            }
        }

        // Split subject from body
        let cleanMessage = messageLines.map { $0 }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let msgParts = cleanMessage.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        subject = msgParts.first.map(String.init) ?? ""
        body = msgParts.count > 1 ? String(msgParts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""

        commitHash = hash
        mergeInfo = merge
        self.author = auth
        self.authorDate = authDate
        self.committer = comm
        self.commitDate = commDate
        changedFiles = files
    }

    private static func isFileStatusLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }
        let first = trimmed.prefix(1)
        let statusChars: Set<Character> = ["M", "A", "D", "R", "C", "T", "U", "X"]
        guard let firstChar = first.first, statusChars.contains(firstChar) else { return false }
        // Must have tab or multiple spaces after status
        return trimmed.dropFirst(1).first == "\t" ||
               (trimmed.count > 2 && trimmed.dropFirst(1).hasPrefix("  "))
    }

    private static func parseFileLine(_ line: String) -> ChangedFile? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return nil }
        let statusChars: Set<Character> = ["M", "A", "D", "R", "C", "T", "U", "X"]
        guard let firstChar = trimmed.first, statusChars.contains(firstChar) else { return nil }

        // Handle tab-separated format: "M\tpath/to/file"
        let parts = trimmed.split(separator: "\t", maxSplits: 1)
        if parts.count == 2 {
            return ChangedFile(status: String(parts[0]).trimmingCharacters(in: .whitespaces), path: String(parts[1]))
        }

        // Handle space-separated format
        let spaceParts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        if spaceParts.count == 2 {
            return ChangedFile(status: String(spaceParts[0]), path: String(spaceParts[1]))
        }

        return nil
    }
}
