import SwiftUI

struct ReviewFindingsView: View {
    let findings: [ReviewFinding]
    var tintColor: Color = DesignSystem.Colors.codeReview
    var onOpenFile: ((String, String?) -> Void)? = nil
    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(tintColor)
                Text(L10n("Code Review")).font(.system(size: 11, weight: .bold))
                Spacer()
                summaryBadges
                if let onDismiss {
                    Button { onDismiss() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            ForEach(findings) { finding in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: finding.severity.icon)
                        .font(.system(size: 10))
                        .foregroundStyle(finding.severity.color)
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        if finding.file != "general" {
                            HStack(spacing: 6) {
                                if let onOpenFile {
                                    Button {
                                        onOpenFile(finding.file, nil)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text(finding.file)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            Image(systemName: "arrow.up.right.square")
                                                .font(.system(size: 8, weight: .semibold))
                                        }
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .cursorArrow()
                                    .help(L10n("Abrir no Editor"))
                                    .accessibilityLabel(L10n("Abrir no Editor"))
                                } else {
                                    Text(finding.file)
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        Text(finding.message)
                            .font(.system(size: 10))
                            .fixedSize(horizontal: false, vertical: true)

                        let snippets = codeSnippets(from: finding.message)
                        if !snippets.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(Array(snippets.prefix(3)), id: \.self) { snippet in
                                        snippetChip(snippet: snippet, file: finding.file)
                                    }
                                }
                                .padding(.top, 2)
                            }
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(finding.severity.color.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
                .overlay(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius).stroke(finding.severity.color.opacity(0.2)))
            }
        }
        .padding(10)
        .background(DesignSystem.Colors.glassSubtle)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius))
    }

    private var summaryBadges: some View {
        HStack(spacing: 6) {
            let criticalCount = findings.filter { $0.severity == .critical }.count
            let warningCount = findings.filter { $0.severity == .warning }.count
            let suggestionCount = findings.filter { $0.severity == .suggestion }.count

            if criticalCount > 0 {
                badge(count: criticalCount, color: DesignSystem.Colors.error, label: L10n("Critico"))
            }
            if warningCount > 0 {
                badge(count: warningCount, color: DesignSystem.Colors.warning, label: L10n("Aviso"))
            }
            if suggestionCount > 0 {
                badge(count: suggestionCount, color: DesignSystem.Colors.info, label: L10n("Sugestao"))
            }
        }
    }

    private func badge(count: Int, color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Text("\(count)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
            Text(label)
                .font(.system(size: 8))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func snippetChip(snippet: String, file: String) -> some View {
        if let onOpenFile, file != "general" {
            Button {
                onOpenFile(file, snippet)
            } label: {
                Text(snippet)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DesignSystem.Colors.glassOverlay)
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(DesignSystem.Colors.glassBorderDark, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .cursorArrow()
            .help(L10n("Abrir no Editor"))
            .accessibilityLabel(L10n("Abrir no Editor"))
        } else {
            Text(snippet)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DesignSystem.Colors.glassOverlay)
                .foregroundStyle(.secondary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(DesignSystem.Colors.glassBorderDark, lineWidth: 1)
                )
        }
    }

    private func codeSnippets(from message: String) -> [String] {
        var snippets: [String] = []
        var current = ""
        var isInsideCode = false

        for char in message {
            if char == "`" {
                if isInsideCode {
                    let snippet = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !snippet.isEmpty && !snippets.contains(snippet) {
                        snippets.append(snippet)
                    }
                    current = ""
                }
                isInsideCode.toggle()
                continue
            }

            if isInsideCode {
                current.append(char)
            }
        }

        return snippets
    }
}
