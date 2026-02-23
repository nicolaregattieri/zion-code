import SwiftUI
import AppKit

struct MarkdownPreviewView: View {
    let markdownText: String
    let fileURL: URL?
    let repositoryURL: URL?
    let theme: EditorTheme

    @State private var blocks: [MarkdownPreviewBlock] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if blocks.isEmpty {
                    emptyStateView
                } else {
                    ForEach(blocks) { block in
                        blockView(block)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .textSelection(.enabled)
        .background(theme.colors.background)
        .environment(\.colorScheme, theme.isLightAppearance ? .light : .dark)
        .environment(\.openURL, OpenURLAction { url in
            openURL(url)
        })
        .onAppear {
            rebuildBlocks()
        }
        .onChange(of: markdownText) { _, _ in
            rebuildBlocks()
        }
        .onChange(of: fileURL?.path) { _, _ in
            rebuildBlocks()
        }
        .onChange(of: repositoryURL?.path) { _, _ in
            rebuildBlocks()
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownPreviewBlock) -> some View {
        switch block.kind {
        case .heading(let text, let level):
            headingView(text: text, level: level)
        case .paragraph(let text):
            markdownTextView(text)
                .font(.system(size: 13))
                .lineSpacing(4)
                .foregroundStyle(theme.colors.text)
        case .blockquote(let text):
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(theme.colors.comment.opacity(0.5))
                    .frame(width: 3)
                    .clipShape(Capsule())
                markdownTextView(text)
                    .font(.system(size: 13))
                    .lineSpacing(4)
                    .foregroundStyle(theme.colors.comment)
                    .padding(.top, 1)
            }
            .padding(.vertical, 2)
        case .code(let code):
            ScrollView(.horizontal) {
                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.colors.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(theme.colors.comment.opacity(theme.isLightAppearance ? 0.12 : 0.2))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius)
                    .stroke(DesignSystem.Colors.glassBorderDark.opacity(0.7), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
        case .image(let alt, let source):
            MarkdownImageView(
                altText: alt,
                source: source,
                resolvedURL: resolveURL(from: source),
                theme: theme
            )
        case .raw(let text):
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(theme.colors.text)
        }
    }

    private func headingView(text: AttributedString, level: Int) -> some View {
        let size: CGFloat
        switch level {
        case 1: size = 26
        case 2: size = 22
        case 3: size = 19
        case 4: size = 17
        case 5: size = 15
        default: size = 14
        }

        return markdownTextView(text)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(theme.colors.text)
            .padding(.top, level <= 2 ? 8 : 4)
    }

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text(L10n("editor.markdown.empty"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(.top, 30)
    }

    private func markdownTextView(_ value: AttributedString) -> Text {
        Text(value)
    }

    private func rebuildBlocks() {
        blocks = Self.parse(markdownText)
    }

    private func openURL(_ url: URL) -> OpenURLAction.Result {
        let resolved: URL
        if url.scheme != nil {
            resolved = url
        } else if let local = resolveURL(from: url.absoluteString) {
            resolved = local
        } else if let local = resolveURL(from: url.path) {
            resolved = local
        } else {
            return .discarded
        }
        NSWorkspace.shared.open(resolved)
        return .handled
    }

    private func resolveURL(from source: String) -> URL? {
        let cleaned = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        guard !cleaned.hasPrefix("#") else { return nil }

        if let absolute = URL(string: cleaned), absolute.scheme != nil {
            return absolute
        }

        if cleaned.hasPrefix("/") {
            guard let repositoryURL else { return nil }
            let path = String(cleaned.dropFirst())
            return repositoryURL.appendingPathComponent(path)
        }

        if let fileURL {
            return fileURL.deletingLastPathComponent().appendingPathComponent(cleaned)
        }

        if let repositoryURL {
            return repositoryURL.appendingPathComponent(cleaned)
        }

        return nil
    }

    private static func parse(_ markdown: String) -> [MarkdownPreviewBlock] {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var result: [MarkdownPreviewBlock] = []
        var paragraphBuffer: [String] = []
        var codeBuffer: [String] = []
        var insideCodeFence = false

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            let text = paragraphBuffer.joined(separator: "\n")
            if let attributed = parseMarkdown(text) {
                result.append(.init(kind: .paragraph(attributed)))
            } else {
                result.append(.init(kind: .raw(text)))
            }
            paragraphBuffer.removeAll(keepingCapacity: true)
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if insideCodeFence {
                    result.append(.init(kind: .code(codeBuffer.joined(separator: "\n"))))
                    codeBuffer.removeAll(keepingCapacity: true)
                    insideCodeFence = false
                } else {
                    flushParagraph()
                    insideCodeFence = true
                }
                continue
            }

            if insideCodeFence {
                codeBuffer.append(line)
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if let image = parseImage(line) {
                flushParagraph()
                result.append(.init(kind: .image(alt: image.alt, source: image.source)))
                continue
            }

            if let heading = parseHeading(line) {
                flushParagraph()
                if let attributed = parseMarkdown(heading.text) {
                    result.append(.init(kind: .heading(attributed, level: heading.level)))
                } else {
                    result.append(.init(kind: .raw(heading.text)))
                }
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                let quote = trimmed.replacingOccurrences(of: #"^>\s?"#, with: "", options: .regularExpression)
                if let attributed = parseMarkdown(quote) {
                    result.append(.init(kind: .blockquote(attributed)))
                } else {
                    result.append(.init(kind: .raw(quote)))
                }
                continue
            }

            paragraphBuffer.append(line)
        }

        if insideCodeFence {
            result.append(.init(kind: .code(codeBuffer.joined(separator: "\n"))))
        }
        if !paragraphBuffer.isEmpty {
            let text = paragraphBuffer.joined(separator: "\n")
            if let attributed = parseMarkdown(text) {
                result.append(.init(kind: .paragraph(attributed)))
            } else {
                result.append(.init(kind: .raw(text)))
            }
        }

        return result
    }

    private static func parseMarkdown(_ text: String) -> AttributedString? {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return try? AttributedString(markdown: text, options: options)
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let pattern = #"^\s*(#{1,6})\s+(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, range: range),
              let levelRange = Range(match.range(at: 1), in: line),
              let textRange = Range(match.range(at: 2), in: line) else {
            return nil
        }
        let level = line[levelRange].count
        let text = String(line[textRange]).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (level, text)
    }

    private static func parseImage(_ line: String) -> (alt: String, source: String)? {
        let pattern = #"^\s*!\[(.*?)\]\(([^)\s]+(?:\s+"[^"]*")?)\)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, range: range),
              let altRange = Range(match.range(at: 1), in: line),
              let srcRange = Range(match.range(at: 2), in: line) else {
            return nil
        }

        let alt = String(line[altRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        var source = String(line[srcRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        if let titleRange = source.range(of: #"\s+\"[^\"]*\"$"#, options: .regularExpression) {
            source = String(source[..<titleRange.lowerBound])
        }
        source = source.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        return source.isEmpty ? nil : (alt, source)
    }
}

private struct MarkdownPreviewBlock: Identifiable {
    enum Kind {
        case heading(AttributedString, level: Int)
        case paragraph(AttributedString)
        case blockquote(AttributedString)
        case code(String)
        case image(alt: String, source: String)
        case raw(String)
    }

    let id = UUID()
    let kind: Kind
}

private struct MarkdownImageView: View {
    let altText: String
    let source: String
    let resolvedURL: URL?
    let theme: EditorTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let resolvedURL {
                if resolvedURL.isFileURL {
                    localImageView(url: resolvedURL)
                } else {
                    remoteImageView(url: resolvedURL)
                }
            } else {
                fallbackView
            }
        }
    }

    @ViewBuilder
    private func localImageView(url: URL) -> some View {
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 360, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
        } else {
            fallbackView
        }
    }

    @ViewBuilder
    private func remoteImageView(url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 360, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
            case .failure:
                fallbackView
            @unknown default:
                fallbackView
            }
        }
    }

    private var fallbackView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n("editor.markdown.imageUnavailable"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.colors.comment)
            Text(source)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.colors.comment.opacity(0.9))
            if !altText.isEmpty {
                Text(altText)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.colors.comment)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.comment.opacity(theme.isLightAppearance ? 0.12 : 0.18))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius)
                .stroke(DesignSystem.Colors.glassBorderDark.opacity(0.7), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
    }
}
