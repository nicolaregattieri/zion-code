import SwiftUI
import AppKit

/// Splits assistant message into prose and code blocks; renders code blocks with
/// monospace background + per-block copy button.
struct AssistantMarkdown: View {

    let content: String

    /// Process-wide chunk cache. Markdown parsing is pure: same content → same chunks.
    /// Avoids re-parsing every SwiftUI body() call (streaming deltas trigger full re-render).
    nonisolated(unsafe) private static var chunkCache: [String: [Chunk]] = [:]
    private static let cacheLimit = 200

    private static func cachedChunks(for source: String) -> [Chunk] {
        if let hit = chunkCache[source] { return hit }
        let chunks = parse(source)
        if chunkCache.count > cacheLimit {
            chunkCache.removeAll(keepingCapacity: true)
        }
        chunkCache[source] = chunks
        return chunks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.compact) {
            ForEach(Array(Self.cachedChunks(for: content).enumerated()), id: \.offset) { _, chunk in
                switch chunk {
                case .prose(let text):
                    proseView(text)
                case .code(let language, let body):
                    CodeBlock(language: language, code: body)
                case .searchReplace(let file, let search, let replace):
                    SearchReplaceCard(file: file, search: search, replace: replace)
                }
            }
        }
    }

    @ViewBuilder
    private func proseView(_ text: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .chatScaledFont(role: .body)
                .chatLineSpacing()
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        } else {
            Text(text)
                .chatScaledFont(role: .body)
                .chatLineSpacing()
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Parsing

    enum Chunk: Equatable {
        case prose(String)
        case code(language: String?, body: String)
        /// Raw aider-style edit block leaked into the assistant text instead of
        /// being parsed into a structured EditBlock card. We still collapse it
        /// to a one-line summary so it doesn't dominate the chat. The user can
        /// expand to inspect the diff.
        case searchReplace(file: String, search: String, replace: String)
    }

    static func parse(_ source: String) -> [Chunk] {
        var chunks: [Chunk] = []
        let lines = source.components(separatedBy: "\n")
        var prose: [String] = []
        var i = 0

        func flushProse() {
            if !prose.isEmpty {
                let joined = prose.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !joined.isEmpty {
                    chunks.append(.prose(joined))
                }
                prose.removeAll()
            }
        }

        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("```") {
                flushProse()
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                chunks.append(.code(language: language.isEmpty ? nil : language, body: codeLines.joined(separator: "\n")))
                i += 1
                continue
            }
            // aider-style SEARCH/REPLACE block (leak from edit harness when
            // parsing fails or model emits raw markers). Header line shape:
            //   <<<<<<< SEARCH[: <path>]
            // Body: <search>\n=======\n<replace>\n>>>>>>> REPLACE
            if line.hasPrefix("<<<<<<<") && line.contains("SEARCH") {
                flushProse()
                // Optional file path after "SEARCH:"
                var file = ""
                if let range = line.range(of: "SEARCH:") {
                    file = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
                var searchLines: [String] = []
                var replaceLines: [String] = []
                var sawDivider = false
                i += 1
                while i < lines.count {
                    let inner = lines[i]
                    if inner.hasPrefix("=======") {
                        sawDivider = true
                        i += 1
                        continue
                    }
                    if inner.hasPrefix(">>>>>>>") && inner.contains("REPLACE") {
                        i += 1
                        break
                    }
                    if sawDivider {
                        replaceLines.append(inner)
                    } else {
                        searchLines.append(inner)
                    }
                    i += 1
                }
                chunks.append(.searchReplace(
                    file: file,
                    search: searchLines.joined(separator: "\n"),
                    replace: replaceLines.joined(separator: "\n")
                ))
                continue
            }
            prose.append(line)
            i += 1
        }
        flushProse()
        return chunks
    }

    func parse(_ source: String) -> [Chunk] {
        Self.parse(source)
    }
}

// MARK: - CodeBlock

private struct CodeBlock: View {
    let language: String?
    let code: String

    @State private var copied = false

    private var codeScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(SyntaxHighlighter.highlight(code, language: language))
                .font(DesignSystem.Typography.monoLabel)
                .textSelection(.enabled)
                .padding(DesignSystem.Spacing.standard)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                if let lang = language, !lang.isEmpty {
                    Text(lang.lowercased())
                        .font(DesignSystem.Typography.metaSemibold)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                } else {
                    Text("code")
                        .font(DesignSystem.Typography.metaSemibold)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                Spacer()
                Button {
                    copy()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                        Text(copied ? L10n("chat.code.copied") : L10n("chat.code.copy"))
                            .font(DesignSystem.Typography.metaSemibold)
                    }
                    .foregroundStyle(copied ? DesignSystem.Colors.success : DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DesignSystem.Spacing.standard)
            .padding(.vertical, DesignSystem.Spacing.compact)
            .background(DesignSystem.Colors.glassHover)

            Rectangle()
                .fill(DesignSystem.Colors.glassBorder)
                .frame(height: 1)

            codeScrollView
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignSystem.Colors.glassElevated)
        }
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous)
                .strokeBorder(DesignSystem.Colors.glassBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous))
    }

    private func copy() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(code, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            copied = false
        }
    }
}

// MARK: - SearchReplaceCard

/// Compact card for raw SEARCH/REPLACE markers leaked into chat text. Default
/// state is COLLAPSED — only the file path + change counts visible. Tap the
/// header to expand a side-by-side preview of the old/new content. Keeps
/// long localization-file diffs from dominating the chat (Image #38 fix).
private struct SearchReplaceCard: View {
    let file: String
    let search: String
    let replace: String

    @State private var isExpanded = false

    private var searchLineCount: Int {
        search.isEmpty ? 0 : search.split(separator: "\n").count
    }

    private var replaceLineCount: Int {
        replace.isEmpty ? 0 : replace.split(separator: "\n").count
    }

    private var displayFile: String {
        file.isEmpty ? L10n("chat.message.searchReplace.unknownFile") : file
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                Divider().overlay(DesignSystem.Colors.glassBorder)
                expandedBody
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous)
                .strokeBorder(DesignSystem.Colors.glassBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous))
        .background(DesignSystem.Colors.glassSubtle)
    }

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                Image(systemName: "arrow.left.arrow.right.square")
                    .foregroundStyle(DesignSystem.Colors.ai)
                    .font(.system(size: 12, weight: .semibold))
                Text(displayFile)
                    .font(DesignSystem.Typography.monoLabelBold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text("−\(searchLineCount)")
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(DesignSystem.Colors.destructive)
                    .monospacedDigit()
                Text("+\(replaceLineCount)")
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(DesignSystem.Colors.success)
                    .monospacedDigit()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .padding(.horizontal, DesignSystem.Spacing.standard)
            .padding(.vertical, DesignSystem.Spacing.compact)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.compact) {
            if !search.isEmpty {
                diffPane(label: L10n("chat.message.searchReplace.search"),
                         body: search,
                         tint: DesignSystem.Colors.destructive)
            }
            if !replace.isEmpty {
                diffPane(label: L10n("chat.message.searchReplace.replace"),
                         body: replace,
                         tint: DesignSystem.Colors.success)
            }
        }
        .padding(DesignSystem.Spacing.standard)
    }

    private func diffPane(label: String, body: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(DesignSystem.Typography.metaSemibold)
                .foregroundStyle(tint)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(body)
                    .font(DesignSystem.Typography.monoLabel)
                    .textSelection(.enabled)
                    .padding(DesignSystem.Spacing.compact)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(tint.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous))
        }
    }
}
