import SwiftUI
import AppKit

struct MarkdownPreviewView: View {
    let markdownText: String
    let fileURL: URL?
    let repositoryURL: URL?
    let theme: EditorTheme

    @State private var blocks: [MarkdownBlock] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.markdownBlockSpacing) {
                if blocks.isEmpty {
                    emptyStateView
                } else {
                    ForEach(blocks) { block in
                        blockView(block)
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.screenEdge)
            .padding(.vertical, DesignSystem.Spacing.sectionGap)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tint(theme.colors.keyword)
        .textSelection(.enabled)
        .background(theme.colors.background)
        .environment(\.colorScheme, theme.isLightAppearance ? .light : .dark)
        .environment(\.openURL, OpenURLAction { url in
            openURL(url)
        })
        .onAppear { rebuildBlocks() }
        .onChange(of: markdownText) { _, _ in rebuildBlocks() }
        .onChange(of: fileURL?.path) { _, _ in rebuildBlocks() }
        .onChange(of: repositoryURL?.path) { _, _ in rebuildBlocks() }
    }

    // MARK: - Block Rendering

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block.kind {
        case .heading(let text, let level):
            headingView(text: text, level: level)
        case .paragraph(let text):
            markdownTextView(text)
                .font(DesignSystem.Typography.cardBody)
                .lineSpacing(4)
                .foregroundStyle(theme.colors.text)
                .padding(.vertical, 6)
        case .blockquote(let lines):
            blockquoteView(lines)
        case .code(let code, let language):
            codeBlockView(code: code, language: language)
        case .image(let alt, let source):
            MarkdownImageView(
                altText: alt,
                source: source,
                resolvedURL: resolveURL(from: source),
                theme: theme
            )
            .padding(.vertical, 6)
        case .horizontalRule:
            horizontalRuleView
        case .list(let items, let ordered):
            listView(items: items, ordered: ordered)
        case .table(let headers, let rows, let alignments):
            tableView(headers: headers, rows: rows, alignments: alignments)
        case .raw(let text):
            Text(text)
                .font(DesignSystem.Typography.cardBody)
                .foregroundStyle(theme.colors.text)
                .padding(.vertical, 4)
        }
    }

    // MARK: - Heading

    private func headingView(text: AttributedString, level: Int) -> some View {
        let headingFont: Font = switch level {
        case 1: DesignSystem.Typography.markdownH1
        case 2: DesignSystem.Typography.markdownH2
        case 3: DesignSystem.Typography.markdownH3
        case 4: DesignSystem.Typography.markdownH4
        case 5: DesignSystem.Typography.markdownH5
        default: DesignSystem.Typography.markdownH6
        }

        return VStack(alignment: .leading, spacing: 0) {
            markdownTextView(text)
                .font(headingFont)
                .foregroundStyle(theme.colors.text)

            if level <= 2 {
                Divider()
                    .overlay(theme.colors.comment.opacity(0.25))
                    .padding(.top, 8)
            }
        }
        .padding(.top, level <= 2 ? 16 : 10)
        .padding(.bottom, level <= 2 ? 8 : 4)
    }

    // MARK: - Blockquote

    private func blockquoteView(_ lines: [AttributedString]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(theme.colors.keyword.opacity(0.5))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    markdownTextView(line)
                        .font(DesignSystem.Typography.cardBody)
                        .lineSpacing(4)
                        .foregroundStyle(theme.colors.comment)
                }
            }
        }
        .padding(DesignSystem.Spacing.cardPadding)
        .background(theme.colors.keyword.opacity(theme.isLightAppearance ? 0.04 : 0.06))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
    }

    // MARK: - Code Block

    private func codeBlockView(code: String, language: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language, !language.isEmpty {
                Text(language)
                    .font(DesignSystem.Typography.monoSmall)
                    .foregroundStyle(theme.colors.comment.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(DesignSystem.Typography.monoBody)
                    .foregroundStyle(theme.colors.text.opacity(0.9))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, language != nil ? 6 : 10)
            }
        }
        .background(theme.colors.comment.opacity(theme.isLightAppearance ? 0.08 : 0.15))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius)
                .stroke(theme.colors.comment.opacity(theme.isLightAppearance ? 0.2 : 0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
        .padding(.vertical, 6)
    }

    // MARK: - Horizontal Rule

    private var horizontalRuleView: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(theme.colors.comment.opacity(0.25))
            .frame(height: 2)
            .padding(.vertical, 16)
    }

    // MARK: - List

    private func listView(items: [MarkdownListItem], ordered: Bool) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.markdownListItemSpacing) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                listItemView(item: item, index: index, ordered: ordered)
            }
        }
        .padding(.vertical, 4)
    }

    private func listItemView(item: MarkdownListItem, index: Int, ordered: Bool) -> some View {
        let indent = CGFloat(item.indentLevel) * 20

        return HStack(alignment: .top, spacing: 0) {
            if let checked = item.isChecked {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(checked ? theme.colors.keyword : theme.colors.comment.opacity(0.5))
                    .frame(width: 20, alignment: .leading)
            } else if ordered {
                Text("\(index + 1).")
                    .font(DesignSystem.Typography.monoCardBody)
                    .foregroundStyle(theme.colors.keyword.opacity(0.7))
                    .frame(width: 24, alignment: .trailing)
                    .padding(.trailing, 6)
            } else {
                let bullet: String = switch item.indentLevel {
                case 0: "\u{2022}"
                case 1: "\u{25E6}"
                default: "\u{2023}"
                }
                Text(bullet)
                    .font(DesignSystem.Typography.cardBody)
                    .foregroundStyle(theme.colors.keyword.opacity(0.6))
                    .frame(width: 16, alignment: .center)
                    .padding(.trailing, 6)
            }

            if let text = item.text {
                markdownTextView(text)
                    .font(DesignSystem.Typography.cardBody)
                    .lineSpacing(4)
                    .foregroundStyle(theme.colors.text)
            }
        }
        .padding(.leading, indent)
        .padding(.vertical, 4)
        .frame(minHeight: 20)
    }

    // MARK: - Table

    private func tableView(headers: [String], rows: [[String]], alignments: [TextAlignment]) -> some View {
        let borderColor = theme.colors.comment.opacity(theme.isLightAppearance ? 0.2 : 0.25)

        return VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                ForEach(Array(headers.enumerated()), id: \.offset) { colIndex, header in
                    let alignment = colIndex < alignments.count ? alignments[colIndex] : .leading

                    Text(header)
                        .font(DesignSystem.Typography.bodySemibold)
                        .foregroundStyle(theme.colors.text)
                        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: horizontalAlignment(alignment), vertical: .center))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)

                    if colIndex < headers.count - 1 {
                        Rectangle().fill(borderColor).frame(width: 1)
                    }
                }
            }
            .background(theme.colors.comment.opacity(theme.isLightAppearance ? 0.08 : 0.12))

            Rectangle().fill(borderColor).frame(height: 1)

            // Data rows
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cell in
                        let alignment = colIndex < alignments.count ? alignments[colIndex] : .leading

                        if let attributed = Self.parseMarkdown(cell) {
                            markdownTextView(attributed)
                                .font(DesignSystem.Typography.body)
                                .foregroundStyle(theme.colors.text)
                                .frame(maxWidth: .infinity, alignment: Alignment(horizontal: horizontalAlignment(alignment), vertical: .center))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        } else {
                            Text(cell)
                                .font(DesignSystem.Typography.body)
                                .foregroundStyle(theme.colors.text)
                                .frame(maxWidth: .infinity, alignment: Alignment(horizontal: horizontalAlignment(alignment), vertical: .center))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }

                        if colIndex < headers.count - 1 {
                            Rectangle().fill(borderColor).frame(width: 1)
                        }
                    }
                }
                .background(rowIndex % 2 == 1 ? theme.colors.comment.opacity(theme.isLightAppearance ? 0.04 : 0.06) : Color.clear)

                if rowIndex < rows.count - 1 {
                    Rectangle().fill(borderColor).frame(height: 1)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius)
                .stroke(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
        .padding(.vertical, 6)
    }

    private func horizontalAlignment(_ alignment: TextAlignment) -> HorizontalAlignment {
        switch alignment {
        case .center: .center
        case .trailing: .trailing
        default: .leading
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(DesignSystem.Typography.settingsTabIcon)
                .foregroundStyle(.secondary)
            Text(L10n("editor.markdown.empty"))
                .font(DesignSystem.Typography.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(.top, 30)
    }

    // MARK: - Helpers

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

    // MARK: - Parser

    fileprivate static func parse(_ markdown: String) -> [MarkdownBlock] {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var result: [MarkdownBlock] = []
        var paragraphBuffer: [String] = []
        var codeBuffer: [String] = []
        var codeLanguage: String?
        var insideCodeFence = false
        var listBuffer: [MarkdownListItem] = []
        var listIsOrdered = false
        var blockquoteBuffer: [String] = []

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

        func flushList() {
            guard !listBuffer.isEmpty else { return }
            result.append(.init(kind: .list(listBuffer, ordered: listIsOrdered)))
            listBuffer.removeAll(keepingCapacity: true)
        }

        func flushBlockquote() {
            guard !blockquoteBuffer.isEmpty else { return }
            let lines = blockquoteBuffer.map { parseMarkdown($0) ?? AttributedString($0) }
            result.append(.init(kind: .blockquote(lines)))
            blockquoteBuffer.removeAll(keepingCapacity: true)
        }

        func flushAll() {
            flushParagraph()
            flushList()
            flushBlockquote()
        }

        var lineIndex = 0
        while lineIndex < lines.count {
            let line = lines[lineIndex]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Code fence
            if trimmed.hasPrefix("```") {
                if insideCodeFence {
                    result.append(.init(kind: .code(codeBuffer.joined(separator: "\n"), language: codeLanguage)))
                    codeBuffer.removeAll(keepingCapacity: true)
                    codeLanguage = nil
                    insideCodeFence = false
                } else {
                    flushAll()
                    let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeLanguage = lang.isEmpty ? nil : lang
                    insideCodeFence = true
                }
                lineIndex += 1
                continue
            }

            if insideCodeFence {
                codeBuffer.append(line)
                lineIndex += 1
                continue
            }

            // Empty line
            if trimmed.isEmpty {
                flushAll()
                lineIndex += 1
                continue
            }

            // Horizontal rule
            if isHorizontalRule(trimmed) {
                flushAll()
                result.append(.init(kind: .horizontalRule))
                lineIndex += 1
                continue
            }

            // Table
            if let table = parseTable(lines: lines, startIndex: lineIndex) {
                flushAll()
                result.append(.init(kind: .table(headers: table.headers, rows: table.rows, alignments: table.alignments)))
                lineIndex = table.endIndex
                continue
            }

            // Image
            if let image = parseImage(line) {
                flushAll()
                result.append(.init(kind: .image(alt: image.alt, source: image.source)))
                lineIndex += 1
                continue
            }

            // Heading
            if let heading = parseHeading(line) {
                flushAll()
                if let attributed = parseMarkdown(heading.text) {
                    result.append(.init(kind: .heading(attributed, level: heading.level)))
                } else {
                    result.append(.init(kind: .raw(heading.text)))
                }
                lineIndex += 1
                continue
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushList()
                let quote = trimmed.replacingOccurrences(of: #"^>\s?"#, with: "", options: .regularExpression)
                blockquoteBuffer.append(quote)
                lineIndex += 1
                continue
            }

            // List item
            if let listItem = parseListItem(line) {
                flushParagraph()
                flushBlockquote()
                if listBuffer.isEmpty {
                    listIsOrdered = listItem.ordered
                }
                listBuffer.append(listItem.item)
                lineIndex += 1
                continue
            }

            // Regular paragraph
            flushList()
            flushBlockquote()
            paragraphBuffer.append(line)
            lineIndex += 1
        }

        if insideCodeFence {
            result.append(.init(kind: .code(codeBuffer.joined(separator: "\n"), language: codeLanguage)))
        }
        flushAll()

        return result
    }

    // MARK: - Inline Parsing

    static func parseMarkdown(_ text: String) -> AttributedString? {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return try? AttributedString(markdown: text, options: options)
    }

    // MARK: - Line Parsers

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

    private static func isHorizontalRule(_ trimmed: String) -> Bool {
        let cleaned = trimmed.replacingOccurrences(of: " ", with: "")
        if cleaned.count < 3 { return false }
        let allSame = cleaned.allSatisfy { $0 == cleaned.first }
        return allSame && (cleaned.first == "-" || cleaned.first == "*" || cleaned.first == "_")
    }

    private static func parseListItem(_ line: String) -> (item: MarkdownListItem, ordered: Bool)? {
        let unorderedPattern = #"^(\s*)([-*+])\s+(.*)$"#
        let orderedPattern = #"^(\s*)\d+[.)]\s+(.*)$"#

        if let regex = try? NSRegularExpression(pattern: unorderedPattern),
           let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)),
           let indentRange = Range(match.range(at: 1), in: line),
           let textRange = Range(match.range(at: 3), in: line) {
            let indent = line[indentRange].count / 2
            let rawText = String(line[textRange])
            let (text, isChecked) = parseCheckbox(rawText)
            let attributed = parseMarkdown(text)
            return (MarkdownListItem(text: attributed, indentLevel: indent, isChecked: isChecked), false)
        }

        if let regex = try? NSRegularExpression(pattern: orderedPattern),
           let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)),
           let indentRange = Range(match.range(at: 1), in: line),
           let textRange = Range(match.range(at: 2), in: line) {
            let indent = line[indentRange].count / 2
            let rawText = String(line[textRange])
            let (text, isChecked) = parseCheckbox(rawText)
            let attributed = parseMarkdown(text)
            return (MarkdownListItem(text: attributed, indentLevel: indent, isChecked: isChecked), true)
        }

        return nil
    }

    private static func parseCheckbox(_ text: String) -> (text: String, isChecked: Bool?) {
        if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
            return (String(text.dropFirst(4)), true)
        }
        if text.hasPrefix("[ ] ") {
            return (String(text.dropFirst(4)), false)
        }
        return (text, nil)
    }

    private static func parseTable(lines: [String], startIndex: Int) -> (headers: [String], rows: [[String]], alignments: [TextAlignment], endIndex: Int)? {
        guard startIndex + 1 < lines.count else { return nil }

        let headerLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
        let separatorLine = lines[startIndex + 1].trimmingCharacters(in: .whitespaces)

        guard headerLine.contains("|"), separatorLine.contains("|") else { return nil }

        let separatorCells = splitTableRow(separatorLine)
        let isSeparator = separatorCells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty || trimmed.range(of: #"^:?-+:?$"#, options: .regularExpression) != nil
        }
        guard isSeparator, !separatorCells.isEmpty else { return nil }

        let headers = splitTableRow(headerLine)
        let alignments: [TextAlignment] = separatorCells.map { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            let left = trimmed.hasPrefix(":")
            let right = trimmed.hasSuffix(":")
            if left && right { return .center }
            if right { return .trailing }
            return .leading
        }

        var rows: [[String]] = []
        var endIndex = startIndex + 2
        while endIndex < lines.count {
            let rowLine = lines[endIndex].trimmingCharacters(in: .whitespaces)
            guard rowLine.contains("|"), !rowLine.isEmpty else { break }
            let cells = splitTableRow(rowLine)
            // Pad or truncate to match header count
            var normalizedCells = cells
            while normalizedCells.count < headers.count { normalizedCells.append("") }
            if normalizedCells.count > headers.count { normalizedCells = Array(normalizedCells.prefix(headers.count)) }
            rows.append(normalizedCells)
            endIndex += 1
        }

        guard !headers.isEmpty else { return nil }
        return (headers, rows, alignments, endIndex)
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var row = line.trimmingCharacters(in: .whitespaces)
        if row.hasPrefix("|") { row = String(row.dropFirst()) }
        if row.hasSuffix("|") { row = String(row.dropLast()) }
        return row.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

// MARK: - Models

private struct MarkdownBlock: Identifiable {
    enum Kind {
        case heading(AttributedString, level: Int)
        case paragraph(AttributedString)
        case blockquote([AttributedString])
        case code(String, language: String?)
        case image(alt: String, source: String)
        case horizontalRule
        case list([MarkdownListItem], ordered: Bool)
        case table(headers: [String], rows: [[String]], alignments: [TextAlignment])
        case raw(String)
    }

    let id = UUID()
    let kind: Kind
}

private struct MarkdownListItem {
    let text: AttributedString?
    let indentLevel: Int
    let isChecked: Bool?
}

// MARK: - Image View

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
                .font(DesignSystem.Typography.bodySemibold)
                .foregroundStyle(theme.colors.comment)
            Text(source)
                .font(DesignSystem.Typography.monoSmall)
                .foregroundStyle(theme.colors.comment.opacity(0.9))
            if !altText.isEmpty {
                Text(altText)
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundStyle(theme.colors.comment)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.comment.opacity(theme.isLightAppearance ? 0.12 : 0.18))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius)
                .stroke(DesignSystem.Colors.glassBorderDark, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
    }
}
