import SwiftUI
import AppKit

/// Splits assistant message into prose and code blocks; renders code blocks with
/// monospace background + per-block copy button.
struct AssistantMarkdown: View {

    let content: String

    /// Process-wide chunk cache. Markdown parsing is pure: same content → same chunks.
    /// Avoids re-parsing every SwiftUI body() call (streaming deltas trigger full re-render).
    private static var chunkCache: [String: [Chunk]] = [:]
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
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        } else {
            Text(text)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Parsing

    enum Chunk: Equatable {
        case prose(String)
        case code(language: String?, body: String)
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
