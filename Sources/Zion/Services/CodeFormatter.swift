import Foundation

// MARK: - Language Mapping

enum FormatterLanguage: String, CaseIterable {
    case json, xml, html, svg, plist
    case javascript, typescript, css, scss, less
    case go, rust, swift
    case python, ruby, shell
    case sql, yaml, liquid, markdown, toml

    static func from(fileExtension ext: String) -> FormatterLanguage? {
        switch ext.lowercased() {
        case "json", "jsonl", "geojson", "webmanifest": return .json
        case "xml": return .xml
        case "html", "htm", "xhtml": return .html
        case "svg": return .svg
        case "plist": return .plist
        case "js", "mjs", "cjs", "jsx": return .javascript
        case "ts", "tsx", "mts", "cts": return .typescript
        case "css": return .css
        case "scss": return .scss
        case "less": return .less
        case "go": return .go
        case "rs": return .rust
        case "swift": return .swift
        case "py", "pyw": return .python
        case "rb": return .ruby
        case "sh", "bash", "zsh", "fish": return .shell
        case "sql": return .sql
        case "yml", "yaml": return .yaml
        case "liquid": return .liquid
        case "md", "markdown": return .markdown
        case "toml": return .toml
        default: return nil
        }
    }
}

// MARK: - Options

struct FormatOptions {
    var tabSize: Int = 4
    var useTabs: Bool = false
    var jsonSortKeys: Bool = false

    var indentUnit: String {
        useTabs ? "\t" : String(repeating: " ", count: tabSize)
    }
}

// MARK: - Error

enum CodeFormatterError: LocalizedError {
    case unsupportedLanguage(String)
    case parseError(String)
    case noChanges

    var errorDescription: String? {
        switch self {
        case .unsupportedLanguage(let ext): return "No formatter for .\(ext)"
        case .parseError(let msg): return "Format error: \(msg)"
        case .noChanges: return "Already formatted"
        }
    }
}

// MARK: - Dispatcher

enum CodeFormatter {

    static func canFormat(fileExtension ext: String) -> Bool {
        FormatterLanguage.from(fileExtension: ext) != nil
    }

    static func format(_ source: String, language: FormatterLanguage, options: FormatOptions) -> Result<String, CodeFormatterError> {
        let result: String
        do {
            switch language {
            case .json:
                result = try JSONFormatter.format(source, options: options)
            case .xml, .html, .svg:
                result = try XMLFormatter.format(source, options: options)
            case .plist:
                result = try PlistFormatter.format(source, options: options)
            case .javascript, .typescript, .go, .rust, .swift:
                result = BraceFormatter.format(source, options: options)
            case .css, .scss, .less:
                result = CSSFormatter.format(source, options: options)
            case .python:
                result = IndentBlockFormatter.formatPython(source, options: options)
            case .ruby:
                result = IndentBlockFormatter.formatRuby(source, options: options)
            case .shell:
                result = IndentBlockFormatter.formatShell(source, options: options)
            case .sql:
                result = SQLFormatter.format(source, options: options)
            case .yaml:
                result = YAMLFormatter.format(source, options: options)
            case .liquid:
                result = LiquidFormatter.format(source, options: options)
            case .markdown:
                result = MarkdownFormatter.format(source, options: options)
            case .toml:
                result = TOMLFormatter.format(source, options: options)
            }
        } catch let error as CodeFormatterError {
            return .failure(error)
        } catch {
            return .failure(.parseError(error.localizedDescription))
        }
        if result == source { return .failure(.noChanges) }
        return .success(result)
    }

    static func format(_ source: String, fileExtension ext: String, options: FormatOptions) -> Result<String, CodeFormatterError> {
        guard let lang = FormatterLanguage.from(fileExtension: ext) else {
            return .failure(.unsupportedLanguage(ext))
        }
        return format(source, language: lang, options: options)
    }
}

// MARK: - Shared Utilities

private func reindent(_ text: String, indent: String) -> String {
    let lines = text.components(separatedBy: "\n")
    guard !lines.isEmpty else { return text }
    // Detect current indent unit (first indented line)
    var detectedUnit: String?
    for line in lines {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        let leading = String(line.prefix(line.count - trimmed.count))
        if !leading.isEmpty {
            if leading.hasPrefix("\t") {
                detectedUnit = "\t"
            } else {
                // Count leading spaces
                let spaces = leading.count
                if spaces > 0 {
                    // Use smallest indent as unit
                    if let current = detectedUnit, current != "\t" {
                        let currentCount = current.count
                        if spaces < currentCount { detectedUnit = leading }
                    } else {
                        detectedUnit = leading
                    }
                }
            }
            break
        }
    }
    guard let srcUnit = detectedUnit, srcUnit != indent else { return text }
    return lines.map { line in
        var depth = 0
        var rest = line[...]
        while rest.hasPrefix(srcUnit) {
            depth += 1
            rest = rest.dropFirst(srcUnit.count)
        }
        return String(repeating: indent, count: depth) + rest
    }.joined(separator: "\n")
}

/// Count occurrences of `char` outside of string literals and comments
private func countOutsideStrings(_ line: String, open: Character, close: Character) -> Int {
    var count = 0
    var inString: Character? = nil
    var escaped = false
    var prev: Character = "\0"
    var inLineComment = false

    for ch in line {
        if inLineComment { break }
        if escaped { escaped = false; prev = ch; continue }
        if ch == "\\" { escaped = true; prev = ch; continue }

        if inString == nil {
            if ch == "/" && prev == "/" { inLineComment = true; continue }
            if ch == "\"" || ch == "'" || ch == "`" {
                inString = ch
            } else if ch == open {
                count += 1
            } else if ch == close {
                count -= 1
            }
        } else if ch == inString {
            inString = nil
        }
        prev = ch
    }
    return count
}

// MARK: - JSON Formatter

private enum JSONFormatter {
    static func format(_ source: String, options: FormatOptions) throws -> String {
        guard let data = source.data(using: .utf8) else {
            throw CodeFormatterError.parseError("Invalid UTF-8")
        }
        let obj: Any
        do {
            obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw CodeFormatterError.parseError(error.localizedDescription)
        }
        var writeOptions: JSONSerialization.WritingOptions = [.prettyPrinted, .fragmentsAllowed]
        if options.jsonSortKeys {
            writeOptions.insert(.sortedKeys)
        }
        let formatted = try JSONSerialization.data(withJSONObject: obj, options: writeOptions)
        guard var result = String(data: formatted, encoding: .utf8) else {
            throw CodeFormatterError.parseError("Could not encode result")
        }
        // JSONSerialization always uses 4-space indent — re-indent if needed
        if options.useTabs || options.tabSize != 4 {
            result = reindent(result, indent: options.indentUnit)
        }
        // Ensure trailing newline
        if !result.hasSuffix("\n") { result += "\n" }
        return result
    }
}

// MARK: - XML Formatter

private enum XMLFormatter {
    static func format(_ source: String, options: FormatOptions) throws -> String {
        let doc: XMLDocument
        do {
            doc = try XMLDocument(xmlString: source, options: [.documentTidyHTML, .nodePreserveWhitespace])
        } catch {
            // Fall back to brace-like formatting for malformed HTML
            return BraceFormatter.format(source, options: options)
        }
        let xmlData = doc.xmlData(options: [.nodePrettyPrint])
        guard var result = String(data: xmlData, encoding: .utf8) else {
            throw CodeFormatterError.parseError("Could not encode XML result")
        }
        // Re-indent to user preference (XMLDocument uses 4-space)
        if options.useTabs || options.tabSize != 4 {
            result = reindent(result, indent: options.indentUnit)
        }
        if !result.hasSuffix("\n") { result += "\n" }
        return result
    }
}

// MARK: - Plist Formatter

private enum PlistFormatter {
    static func format(_ source: String, options: FormatOptions) throws -> String {
        guard let data = source.data(using: .utf8) else {
            throw CodeFormatterError.parseError("Invalid UTF-8")
        }
        let obj: Any
        var format = PropertyListSerialization.PropertyListFormat.xml
        do {
            obj = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
        } catch {
            throw CodeFormatterError.parseError(error.localizedDescription)
        }
        let xmlData = try PropertyListSerialization.data(fromPropertyList: obj, format: .xml, options: 0)
        guard var result = String(data: xmlData, encoding: .utf8) else {
            throw CodeFormatterError.parseError("Could not encode plist result")
        }
        if options.useTabs || options.tabSize != 4 {
            result = reindent(result, indent: options.indentUnit)
        }
        if !result.hasSuffix("\n") { result += "\n" }
        return result
    }
}

// MARK: - Brace Formatter (JS/TS, Go, Rust, Swift)

private enum BraceFormatter {
    static func format(_ source: String, options: FormatOptions) -> String {
        let lines = source.components(separatedBy: "\n")
        var result: [String] = []
        var depth = 0
        let indent = options.indentUnit

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { result.append(""); continue }

            // Decrease depth before the line if it starts with closing brace/bracket
            let leadingCloses = trimmed.prefix(while: { $0 == "}" || $0 == ")" || $0 == "]" })
            if !leadingCloses.isEmpty {
                depth -= leadingCloses.count
                if depth < 0 { depth = 0 }
            }

            result.append(String(repeating: indent, count: depth) + trimmed)

            // Adjust depth based on full line content
            let delta = countOutsideStrings(trimmed, open: "{", close: "}")
                + countOutsideStrings(trimmed, open: "(", close: ")")
                + countOutsideStrings(trimmed, open: "[", close: "]")
            // We already accounted for leading closes, so re-add them
            depth += delta + leadingCloses.count
            if depth < 0 { depth = 0 }
        }

        var text = result.joined(separator: "\n")
        if !text.hasSuffix("\n") { text += "\n" }
        return text
    }
}

// MARK: - CSS Formatter

private enum CSSFormatter {
    static func format(_ source: String, options: FormatOptions) -> String {
        let lines = source.components(separatedBy: "\n")
        var result: [String] = []
        var depth = 0
        let indent = options.indentUnit

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { result.append(""); continue }

            // Split compound statements (multiple declarations on one line)
            let parts = splitCSSStatements(trimmed)
            for part in parts {
                let t = part.trimmingCharacters(in: .whitespaces)
                if t.isEmpty { continue }

                if t.hasPrefix("}") {
                    depth = max(0, depth - 1)
                    result.append(String(repeating: indent, count: depth) + t)
                } else {
                    result.append(String(repeating: indent, count: depth) + t)
                }

                if t.hasSuffix("{") {
                    depth += 1
                } else if t.contains("}") && !t.hasPrefix("}") {
                    let opens = t.filter { $0 == "{" }.count
                    let closes = t.filter { $0 == "}" }.count
                    depth += opens - closes
                    if depth < 0 { depth = 0 }
                }
            }
        }

        var text = result.joined(separator: "\n")
        if !text.hasSuffix("\n") { text += "\n" }
        return text
    }

    private static func splitCSSStatements(_ line: String) -> [String] {
        // Split "property: value; property: value;" into separate lines when inside a rule
        guard line.contains(";") && !line.contains("{") && !line.contains("}") else {
            return [line]
        }
        let parts = line.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        return parts.filter { !$0.isEmpty }.map { $0 + ";" }
    }
}

// MARK: - Indent Block Formatter (Python, Ruby, Shell)

private enum IndentBlockFormatter {
    static func formatPython(_ source: String, options: FormatOptions) -> String {
        // Normalize indentation only — don't restructure Python
        var result = reindent(source, indent: options.indentUnit)
        // Strip trailing whitespace per line
        result = result.components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
            .joined(separator: "\n")
        if !result.hasSuffix("\n") { result += "\n" }
        return result
    }

    static func formatRuby(_ source: String, options: FormatOptions) -> String {
        let lines = source.components(separatedBy: "\n")
        var result: [String] = []
        var depth = 0
        let indent = options.indentUnit

        let openers = ["def", "class", "module", "if", "unless", "case", "while", "until", "for", "do", "begin"]
        let closers = ["end"]

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { result.append(""); continue }

            let firstWord = String(trimmed.prefix(while: { $0.isLetter || $0 == "_" }))

            if closers.contains(firstWord) || trimmed.hasPrefix("elsif") || trimmed.hasPrefix("else") ||
                trimmed.hasPrefix("when") || trimmed.hasPrefix("rescue") || trimmed.hasPrefix("ensure") {
                if closers.contains(firstWord) { depth = max(0, depth - 1) }
                else { depth = max(0, depth - 1) } // dedent then re-indent
                result.append(String(repeating: indent, count: depth) + trimmed)
                if !closers.contains(firstWord) { depth += 1 }
            } else {
                result.append(String(repeating: indent, count: depth) + trimmed)
                // Check if line opens a block
                if openers.contains(firstWord) || trimmed.hasSuffix(" do") || trimmed.hasSuffix(" do |") {
                    depth += 1
                }
                // Inline block on one line doesn't increase depth
                if trimmed.contains(" end") && (trimmed.hasSuffix(" end") || trimmed.hasSuffix(" end;")) {
                    depth = max(0, depth - 1)
                }
            }
        }

        var text = result.joined(separator: "\n")
        if !text.hasSuffix("\n") { text += "\n" }
        return text
    }

    static func formatShell(_ source: String, options: FormatOptions) -> String {
        let lines = source.components(separatedBy: "\n")
        var result: [String] = []
        var depth = 0
        let indent = options.indentUnit

        let openers: Set<String> = ["if", "for", "while", "until", "case", "select"]
        let closers: Set<String> = ["fi", "done", "esac"]
        let midKeywords: Set<String> = ["else", "elif"]

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { result.append(""); continue }

            let firstWord = String(trimmed.prefix(while: { $0.isLetter || $0 == "_" }))

            if closers.contains(firstWord) {
                depth = max(0, depth - 1)
                result.append(String(repeating: indent, count: depth) + trimmed)
            } else if midKeywords.contains(firstWord) {
                result.append(String(repeating: indent, count: max(0, depth - 1)) + trimmed)
            } else {
                result.append(String(repeating: indent, count: depth) + trimmed)
            }

            if openers.contains(firstWord) || trimmed.hasSuffix("then") || trimmed.hasSuffix("do") ||
                trimmed.hasSuffix("{") {
                depth += 1
            }
            // ";;)" in case doesn't affect depth
        }

        var text = result.joined(separator: "\n")
        if !text.hasSuffix("\n") { text += "\n" }
        return text
    }
}

// MARK: - SQL Formatter

private enum SQLFormatter {
    static func format(_ source: String, options: FormatOptions) -> String {
        let indent = options.indentUnit
        let keywords: Set<String> = [
            "SELECT", "FROM", "WHERE", "AND", "OR", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER",
            "ON", "GROUP", "ORDER", "HAVING", "LIMIT", "OFFSET", "INSERT", "INTO", "VALUES",
            "UPDATE", "SET", "DELETE", "CREATE", "ALTER", "DROP", "TABLE", "INDEX", "VIEW",
            "UNION", "ALL", "AS", "IN", "NOT", "NULL", "IS", "LIKE", "BETWEEN", "EXISTS",
            "CASE", "WHEN", "THEN", "ELSE", "END", "BEGIN", "COMMIT", "ROLLBACK",
            "WITH", "DISTINCT", "TOP", "ASC", "DESC",
        ]

        let clauseStarters: Set<String> = [
            "SELECT", "FROM", "WHERE", "GROUP BY", "ORDER BY", "HAVING",
            "LIMIT", "OFFSET", "UNION", "INSERT INTO", "VALUES", "UPDATE",
            "SET", "DELETE FROM", "CREATE", "ALTER", "DROP", "WITH",
        ]

        // Uppercase keywords
        var text = source
        for kw in keywords {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: kw.lowercased()))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..., in: text)
                text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: kw)
            }
        }

        // Add newlines before major clauses
        var result = text
        for clause in clauseStarters {
            let pattern = "(?<=[^ \\n])\\s+(\(NSRegularExpression.escapedPattern(for: clause))\\b)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "\n$1")
            }
        }

        // Indent continuation lines (AND, OR, ON)
        let lines = result.components(separatedBy: "\n")
        var formatted: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { formatted.append(""); continue }
            let upper = trimmed.uppercased()
            if upper.hasPrefix("AND ") || upper.hasPrefix("OR ") || upper.hasPrefix("ON ") {
                formatted.append(indent + trimmed)
            } else {
                formatted.append(trimmed)
            }
        }

        var finalText = formatted.joined(separator: "\n")
        if !finalText.hasSuffix("\n") { finalText += "\n" }
        return finalText
    }
}

// MARK: - YAML Formatter

private enum YAMLFormatter {
    static func format(_ source: String, options: FormatOptions) -> String {
        var lines = source.components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }

        // Normalize indent
        let result = reindent(lines.joined(separator: "\n"), indent: options.indentUnit)
        lines = result.components(separatedBy: "\n")

        // Remove excessive blank lines (max 1 consecutive)
        var output: [String] = []
        var lastBlank = false
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !lastBlank { output.append("") }
                lastBlank = true
            } else {
                output.append(line)
                lastBlank = false
            }
        }

        var text = output.joined(separator: "\n")
        if !text.hasSuffix("\n") { text += "\n" }
        return text
    }
}

// MARK: - Liquid Formatter

private enum LiquidFormatter {
    static func format(_ source: String, options: FormatOptions) -> String {
        let lines = source.components(separatedBy: "\n")
        var result: [String] = []
        var depth = 0
        let indent = options.indentUnit

        let blockTags: Set<String> = [
            "if", "unless", "for", "case", "capture", "form", "paginate",
            "tablerow", "block", "schema", "style", "javascript", "raw", "comment",
        ]
        let midTags: Set<String> = ["else", "elsif", "when"]

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { result.append(""); continue }

            // Check for {%- endXXX -%} or {% endXXX %}
            let isEndTag = trimmed.range(of: "\\{%-?\\s*end\\w+", options: .regularExpression) != nil
            let isMidTag = midTags.contains(where: { tag in
                trimmed.range(of: "\\{%-?\\s*\(tag)", options: .regularExpression) != nil
            })
            let isOpenTag = blockTags.contains(where: { tag in
                trimmed.range(of: "\\{%-?\\s*\(tag)", options: .regularExpression) != nil
            })

            if isEndTag {
                depth = max(0, depth - 1)
                result.append(String(repeating: indent, count: depth) + trimmed)
            } else if isMidTag {
                result.append(String(repeating: indent, count: max(0, depth - 1)) + trimmed)
            } else {
                result.append(String(repeating: indent, count: depth) + trimmed)
                if isOpenTag { depth += 1 }
            }
        }

        var text = result.joined(separator: "\n")
        if !text.hasSuffix("\n") { text += "\n" }
        return text
    }
}

// MARK: - Markdown Formatter

private enum MarkdownFormatter {
    static func format(_ source: String, options: FormatOptions) -> String {
        let lines = source.components(separatedBy: "\n")
        var result: [String] = []
        var prevWasBlank = false
        var prevWasHeading = false

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Normalize heading spacing: ensure blank line before headings
            if trimmed.hasPrefix("#") && i > 0 {
                if !prevWasBlank && !result.isEmpty {
                    result.append("")
                }
            }

            // Ensure blank line after headings
            if prevWasHeading && !trimmed.isEmpty && !trimmed.hasPrefix("#") && !prevWasBlank {
                result.append("")
            }

            // Collapse multiple blank lines to one
            let isBlank = trimmed.isEmpty
            if isBlank {
                if !prevWasBlank { result.append("") }
                prevWasBlank = true
                prevWasHeading = false
                continue
            }

            // Normalize list indentation
            if trimmed.range(of: "^(\\s*)([-*+]|\\d+\\.)\\s", options: .regularExpression) != nil {
                result.append(trimmed) // Keep list items as-is (already trimmed)
            } else {
                result.append(trimmed)
            }

            prevWasBlank = false
            prevWasHeading = trimmed.hasPrefix("#")
        }

        // Strip trailing blank lines
        while result.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            result.removeLast()
        }

        var text = result.joined(separator: "\n")
        if !text.hasSuffix("\n") { text += "\n" }
        return text
    }
}

// MARK: - TOML Formatter

private enum TOMLFormatter {
    static func format(_ source: String, options: FormatOptions) -> String {
        let lines = source.components(separatedBy: "\n")
        var result: [String] = []
        var prevWasBlank = false

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Blank line before section headers
            if trimmed.hasPrefix("[") && !trimmed.hasPrefix("[[") || trimmed.hasPrefix("[[") {
                if i > 0 && !prevWasBlank && !result.isEmpty {
                    result.append("")
                }
                result.append(trimmed)
                prevWasBlank = false
                continue
            }

            // Collapse multiple blank lines
            if trimmed.isEmpty {
                if !prevWasBlank { result.append("") }
                prevWasBlank = true
                continue
            }

            // Normalize key = value spacing
            if let eqRange = findTOMLEquals(trimmed) {
                let key = trimmed[trimmed.startIndex..<eqRange.lowerBound].trimmingCharacters(in: .whitespaces)
                let value = trimmed[eqRange.upperBound...].trimmingCharacters(in: .whitespaces)
                result.append("\(key) = \(value)")
            } else {
                result.append(trimmed)
            }

            prevWasBlank = false
        }

        // Strip trailing blanks
        while result.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            result.removeLast()
        }

        var text = result.joined(separator: "\n")
        if !text.hasSuffix("\n") { text += "\n" }
        return text
    }

    private static func findTOMLEquals(_ line: String) -> Range<String.Index>? {
        // Find '=' outside of quotes
        var inString: Character? = nil
        for i in line.indices {
            let ch = line[i]
            if inString != nil {
                if ch == inString { inString = nil }
            } else if ch == "\"" || ch == "'" {
                inString = ch
            } else if ch == "=" {
                return i..<line.index(after: i)
            }
        }
        return nil
    }
}
