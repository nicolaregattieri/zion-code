import SwiftUI

/// Lightweight regex-based syntax highlighter for chat code blocks.
/// Token coverage: keywords, types, strings, numbers, comments, function names, attributes.
enum SyntaxHighlighter {

    /// Memoize highlighted AttributedString per (source, language) to skip regex passes
    /// on every SwiftUI body call (streaming deltas re-render the whole tree).
    private static var cache: [String: AttributedString] = [:]
    private static let cacheLimit = 200

    static func highlight(_ source: String, language: String?) -> AttributedString {
        let lang = normalize(language)
        let key = "\(lang)::\(source)"
        if let hit = cache[key] { return hit }
        if cache.count > cacheLimit {
            cache.removeAll(keepingCapacity: true)
        }
        var attributed = AttributedString(source)
        let nsSource = source as NSString
        let fullRange = NSRange(location: 0, length: nsSource.length)

        // Base font + foreground
        for run in attributed.runs {
            attributed[run.range].foregroundColor = DesignSystem.Colors.textPrimary
        }
        attributed.font = DesignSystem.Typography.monoLabel

        let tokens = tokenSet(for: lang)
        for token in tokens {
            apply(token: token, to: &attributed, in: nsSource, fullRange: fullRange)
        }
        cache[key] = attributed
        return attributed
    }

    // MARK: - Token sets

    private struct Token {
        let pattern: String
        let color: Color
        let bold: Bool
        let options: NSRegularExpression.Options

        init(_ pattern: String, _ color: Color, bold: Bool = false, options: NSRegularExpression.Options = []) {
            self.pattern = pattern
            self.color = color
            self.bold = bold
            self.options = options
        }
    }

    private static func tokenSet(for lang: String) -> [Token] {
        let stringColor = Color(red: 0xCE/255, green: 0x91/255, blue: 0x78/255)  // soft orange
        let keywordColor = Color(red: 0xF6/255, green: 0x7B/255, blue: 0xA8/255) // pink
        let typeColor = Color(red: 0x4E/255, green: 0xC9/255, blue: 0xB0/255)    // cyan
        let numberColor = Color(red: 0xB5/255, green: 0xCE/255, blue: 0xA8/255)  // muted green
        let commentColor = Color(red: 0x6A/255, green: 0x99/255, blue: 0x55/255).opacity(0.8) // dim olive
        let funcColor = Color(red: 0xDC/255, green: 0xDC/255, blue: 0xAA/255)    // pale yellow
        let attrColor = Color(red: 0xD1/255, green: 0x9A/255, blue: 0x66/255)    // amber

        // Always include strings, numbers, comments (universal)
        let universal: [Token] = [
            Token("//[^\\n]*", commentColor),                                  // line comment
            Token("/\\*[\\s\\S]*?\\*/", commentColor),                          // block comment
            Token("\"(?:\\\\.|[^\"\\\\])*\"", stringColor),                    // double-quoted string
            Token("'(?:\\\\.|[^'\\\\])*'", stringColor),                       // single-quoted string
            Token("\\b\\d+(?:\\.\\d+)?\\b", numberColor),                      // numbers
        ]

        switch lang {
        case "swift":
            return universal + [
                Token("@\\w+", attrColor),                                      // attributes @MainActor etc
                Token("\\b(func|let|var|if|else|guard|return|switch|case|default|for|in|while|do|try|catch|throw|throws|async|await|struct|class|enum|extension|protocol|init|deinit|self|super|private|public|internal|fileprivate|open|static|final|nil|true|false|import|typealias|where|as|is|inout|associatedtype|defer|repeat|break|continue|fallthrough|@escaping|@Sendable)\\b", keywordColor, bold: true),
                Token("\\b(Int|String|Double|Float|Bool|Array|Dictionary|Set|Optional|UUID|URL|Date|Data|Error|Result|Task|AsyncStream|AsyncThrowingStream|Sendable|View|Color|Image|Text|HStack|VStack|ZStack|some|any|Void|Never)\\b", typeColor),
                Token("\\b([a-z_][a-zA-Z0-9_]*)\\s*(?=\\()", funcColor),       // func calls
            ]
        case "javascript", "typescript", "tsx", "jsx":
            return universal + [
                Token("`(?:\\\\.|[^`\\\\])*`", stringColor),                    // template literals
                Token("\\b(const|let|var|function|return|if|else|switch|case|default|for|while|do|break|continue|new|class|extends|super|this|import|export|from|default|async|await|try|catch|finally|throw|typeof|instanceof|in|of|delete|void|null|undefined|true|false|interface|type|enum|public|private|protected|readonly|static|abstract|implements)\\b", keywordColor, bold: true),
                Token("\\b(string|number|boolean|object|any|unknown|never|void|Array|Promise|Record|Partial|Readonly|Required|Pick|Omit|Map|Set|Date|RegExp|Error|JSON|Math|Number|String|Boolean|Object)\\b", typeColor),
                Token("\\b([a-z_$][a-zA-Z0-9_$]*)\\s*(?=\\()", funcColor),
            ]
        case "python":
            return universal + [
                Token("#[^\\n]*", commentColor),
                Token("\\b(def|class|if|elif|else|for|while|return|import|from|as|pass|break|continue|try|except|finally|raise|with|lambda|yield|global|nonlocal|in|is|not|and|or|None|True|False|self|cls|async|await)\\b", keywordColor, bold: true),
                Token("\\b(int|str|float|bool|list|dict|set|tuple|bytes|object|type)\\b", typeColor),
                Token("@\\w+", attrColor),
                Token("\\b([a-z_][a-zA-Z0-9_]*)\\s*(?=\\()", funcColor),
            ]
        case "rust":
            return universal + [
                Token("\\b(fn|let|mut|const|static|if|else|match|return|for|while|loop|break|continue|struct|enum|impl|trait|pub|use|mod|crate|self|Self|super|where|async|await|move|ref|as|in|unsafe|true|false|None|Some|Ok|Err)\\b", keywordColor, bold: true),
                Token("\\b(i8|i16|i32|i64|i128|u8|u16|u32|u64|u128|f32|f64|bool|char|str|String|Vec|Option|Result|Box|Arc|Rc|HashMap|HashSet|usize|isize)\\b", typeColor),
                Token("\\b([a-z_][a-zA-Z0-9_]*)\\s*(?=\\()", funcColor),
            ]
        case "go":
            return universal + [
                Token("\\b(func|var|const|type|struct|interface|if|else|switch|case|default|for|range|return|break|continue|fallthrough|defer|go|select|chan|map|package|import|nil|true|false|iota)\\b", keywordColor, bold: true),
                Token("\\b(int|int8|int16|int32|int64|uint|uint8|uint16|uint32|uint64|float32|float64|bool|string|byte|rune|error)\\b", typeColor),
                Token("\\b([a-z_][a-zA-Z0-9_]*)\\s*(?=\\()", funcColor),
            ]
        case "json":
            return [
                Token("\"(?:\\\\.|[^\"\\\\])*\"\\s*(?=:)", typeColor),          // keys
                Token("\"(?:\\\\.|[^\"\\\\])*\"", stringColor),                // values
                Token("\\b\\d+(?:\\.\\d+)?\\b", numberColor),
                Token("\\b(true|false|null)\\b", keywordColor),
            ]
        case "bash", "sh", "shell", "zsh":
            return universal + [
                Token("#[^\\n]*", commentColor),
                Token("\\b(if|then|else|elif|fi|case|esac|for|while|do|done|function|return|in|exit|export|local|readonly|declare)\\b", keywordColor, bold: true),
                Token("\\$[A-Za-z_][A-Za-z0-9_]*", attrColor),
                Token("\\$\\{[^}]+\\}", attrColor),
            ]
        default:
            return universal
        }
    }

    private static func normalize(_ language: String?) -> String {
        guard let raw = language?.lowercased(), !raw.isEmpty else { return "" }
        switch raw {
        case "js": return "javascript"
        case "ts": return "typescript"
        case "py": return "python"
        case "rs": return "rust"
        case "yml": return "yaml"
        default: return raw
        }
    }

    private static func apply(token: Token, to attributed: inout AttributedString, in nsSource: NSString, fullRange: NSRange) {
        guard let regex = try? NSRegularExpression(pattern: token.pattern, options: token.options) else { return }
        let matches = regex.matches(in: nsSource as String, options: [], range: fullRange)
        for match in matches {
            // For patterns with capture groups (func names), color only the group 1
            let target = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
            guard target.location != NSNotFound else { continue }
            guard let swiftRange = Range(target, in: nsSource as String) else { continue }
            guard let attrRange = Range(swiftRange, in: attributed) else { continue }
            attributed[attrRange].foregroundColor = token.color
            if token.bold {
                attributed[attrRange].font = DesignSystem.Typography.monoLabel.weight(.semibold)
            }
        }
    }
}
