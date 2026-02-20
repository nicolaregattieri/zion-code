import SwiftUI
import AppKit

struct SourceCodeEditor: NSViewRepresentable {
    @Binding var text: String
    var theme: EditorTheme
    var fontSize: Double = 13.0
    var fontFamily: String = "SF Mono"
    var lineSpacing: Double = 1.2
    var isLineWrappingEnabled: Bool = true
    var activeFileID: String?
    var fileExtension: String = ""

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont(name: fontFamily, size: fontSize)
            ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.usesAdaptiveColorMappingForDarkAppearance = false
        
        // Setup Line Numbers
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        let ruler = LineNumberRulerView(textView: textView)
        ruler.theme = theme
        scrollView.verticalRulerView = ruler

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        // Sync text
        if textView.string != text {
            textView.string = text
        }

        // Sync font
        let font = NSFont(name: fontFamily, size: fontSize)
            ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if textView.font != font {
            textView.font = font
        }

        // Handle Line Wrapping
        if isLineWrappingEnabled {
            textView.isHorizontallyResizable = false
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.containerSize = NSSize(width: nsView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        } else {
            textView.isHorizontallyResizable = true
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }

        let colors = getEditorColors(for: theme)
        textView.drawsBackground = true
        textView.backgroundColor = colors.background
        nsView.drawsBackground = true
        nsView.backgroundColor = colors.background
        textView.insertionPointColor = colors.text

        if let ruler = nsView.verticalRulerView as? LineNumberRulerView {
            ruler.theme = theme
            ruler.needsDisplay = true
        }

        // Highlighting
        let coord = context.coordinator
        let currentText = textView.string
        if currentText != coord.lastHighlightedText || theme != coord.lastHighlightedTheme || fileExtension != coord.lastHighlightedExtension {
            coord.applyHighlighting(to: textView, colors: colors)
            coord.lastHighlightedText = currentText
            coord.lastHighlightedTheme = theme
            coord.lastHighlightedExtension = fileExtension
        }

        // Apply line spacing
        let range = NSRange(location: 0, length: textView.string.utf16.count)
        if range.length > 0 {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = CGFloat(lineSpacing)
            textView.textStorage?.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        }

        // Scroll to top-left only when the active file changes
        if activeFileID != context.coordinator.lastActiveFileID {
            context.coordinator.lastActiveFileID = activeFileID
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                textView.setSelectedRange(NSRange(location: 0, length: 0))
                textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SourceCodeEditor
        var lastActiveFileID: String?
        var lastHighlightedText: String?
        var lastHighlightedTheme: EditorTheme?
        var lastHighlightedExtension: String?
        var regexCache: [String: NSRegularExpression] = [:]
        init(_ parent: SourceCodeEditor) { self.parent = parent }

        @MainActor
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if parent.text != textView.string {
                parent.text = textView.string
            }
            let colors = parent.getEditorColors(for: parent.theme)
            applyHighlighting(to: textView, colors: colors)
            lastHighlightedText = textView.string
            lastHighlightedTheme = parent.theme
            lastHighlightedExtension = parent.fileExtension
            textView.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }

        private enum LanguageType {
            case swift, javascript, python, rust, go, ruby, html, css, json, yaml, markdown, shell, cLike, sql, lua, liquid, unknown
        }

        private func detectLanguage(from ext: String) -> LanguageType {
            switch ext.lowercased() {
            case "swift": return .swift
            case "js", "jsx", "ts", "tsx", "mjs", "cjs", "mts", "cts", "graphql", "gql": return .javascript
            case "py", "pyw", "r": return .python
            case "rs": return .rust
            case "go": return .go
            case "rb", "ex", "exs": return .ruby
            case "html", "htm", "xml", "svg", "vue", "svelte", "erb", "ejs", "hbs", "njk": return .html
            case "liquid": return .liquid
            case "css", "scss", "sass", "less": return .css
            case "json": return .json
            case "yaml", "yml", "toml", "ini", "cfg", "conf", "properties", "env": return .yaml
            case "md", "markdown": return .markdown
            case "sh", "bash", "zsh", "fish", "dockerfile": return .shell
            case "c", "h", "cpp", "cc", "cxx", "hpp", "m", "mm", "java", "kt", "cs",
                 "dart", "zig", "v", "php", "tf", "hcl", "prisma", "pl", "pm": return .cLike
            case "sql": return .sql
            case "lua": return .lua
            default: return .unknown
            }
        }

        private func keywordsPattern(for lang: LanguageType) -> String {
            switch lang {
            case .swift:
                return #"\b(func|let|var|class|struct|import|if|else|return|while|for|in|switch|case|break|continue|enum|protocol|extension|typealias|try|catch|guard|static|public|private|internal|fileprivate|open|override|final|async|await|do|self|throw|throws|as|is|where|nil|true|false|some|any|init|deinit|subscript|operator|precedencegroup|associatedtype|inout|mutating|nonmutating|convenience|required|lazy|weak|unowned|willSet|didSet|get|set|defer|repeat|fallthrough|indirect|macro)\b"#
            case .javascript:
                return #"\b(function|const|let|var|class|if|else|return|while|for|in|of|switch|case|break|continue|import|export|from|default|new|this|try|catch|finally|throw|async|await|yield|typeof|instanceof|void|delete|null|undefined|true|false|super|extends|implements|interface|type|enum|namespace|module|declare|abstract|as|is|keyof|readonly|static|public|private|protected|get|set|constructor)\b"#
            case .python:
                return #"\b(def|class|if|elif|else|return|while|for|in|import|from|as|try|except|finally|raise|with|yield|lambda|pass|break|continue|and|or|not|is|None|True|False|global|nonlocal|assert|del|async|await|self|super|match|case)\b"#
            case .rust:
                return #"\b(fn|let|mut|const|struct|enum|impl|trait|pub|use|mod|if|else|return|while|for|in|loop|match|break|continue|async|await|move|ref|self|Self|super|crate|type|where|as|unsafe|extern|dyn|static|true|false|None|Some|Ok|Err|Box|Vec|String|Option|Result)\b"#
            case .go:
                return #"\b(func|var|const|type|struct|interface|if|else|return|for|range|switch|case|break|continue|import|package|go|defer|select|chan|map|make|new|append|len|cap|true|false|nil|error|string|int|bool|byte|rune|float32|float64|int32|int64|uint)\b"#
            case .ruby:
                return #"\b(def|class|module|if|elsif|else|unless|return|while|for|in|do|end|begin|rescue|ensure|raise|yield|block_given\?|require|include|extend|attr_accessor|attr_reader|attr_writer|self|super|nil|true|false|and|or|not|puts|print|lambda|proc)\b"#
            case .shell:
                return #"\b(if|then|else|elif|fi|for|while|do|done|case|esac|in|function|return|local|export|source|echo|exit|test|read|shift|set|unset|readonly|declare|typeset|eval|exec|trap|wait|cd|pwd|true|false)\b"#
            case .cLike:
                return #"\b(auto|break|case|char|const|continue|default|do|double|else|enum|extern|float|for|goto|if|inline|int|long|register|restrict|return|short|signed|sizeof|static|struct|switch|typedef|union|unsigned|void|volatile|while|class|namespace|template|typename|this|new|delete|public|private|protected|virtual|override|final|try|catch|throw|using|true|false|null|nullptr|bool|string|import|package|interface|implements|extends|abstract|synchronized|native|assert)\b"#
            case .sql:
                return #"(?i)\b(select|from|where|insert|into|update|set|delete|create|alter|drop|table|index|view|join|inner|outer|left|right|cross|on|and|or|not|in|is|null|like|between|exists|having|group|by|order|asc|desc|limit|offset|union|all|as|distinct|case|when|then|else|end|begin|commit|rollback|transaction|grant|revoke|primary|key|foreign|references|constraint|default|values|count|sum|avg|min|max|cast|coalesce|if|function|procedure|trigger|returns|declare|cursor|fetch|into|varchar|int|integer|text|boolean|date|timestamp|float|double|decimal|serial|auto_increment|unique|check|truncate)\b"#
            case .lua:
                return #"\b(and|break|do|else|elseif|end|false|for|function|goto|if|in|local|nil|not|or|repeat|return|then|true|until|while|require|self|pairs|ipairs|next|type|tostring|tonumber|print|error|pcall|xpcall|setmetatable|getmetatable|rawget|rawset|select|unpack|table|string|math|io|os|coroutine)\b"#
            case .liquid:
                return #"\b(if|else|elsif|endif|unless|endunless|case|when|endcase|for|endfor|tablerow|endtablerow|assign|capture|endcapture|increment|decrement|comment|endcomment|raw|endraw|include|render|layout|section)\b"#
            case .html, .css, .json, .yaml, .markdown, .unknown:
                return #"\b(func|let|var|class|struct|import|if|else|return|while|for|in|switch|case|break|continue|enum|protocol|extension|typealias|try|catch|guard|static|public|private|true|false|null|nil)\b"#
            }
        }

        @MainActor
        func applyHighlighting(to textView: NSTextView, colors: EditorColors) {
            let string = textView.string
            let length = string.utf16.count
            guard length > 0, let textStorage = textView.textStorage else { return }
            let range = NSRange(location: 0, length: length)
            let lang = detectLanguage(from: parent.fileExtension)

            textStorage.beginEditing()

            // 1. Reset all attributes
            textStorage.setAttributes([
                .foregroundColor: colors.text,
                .font: textView.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            ], range: range)

            // 2. Language highlighting
            switch lang {
            case .json:
                highlight(pattern: #""[^"\\]*(?:\\.[^"\\]*)*"\s*:"#, in: string, color: colors.keyword, storage: textStorage)
                highlight(pattern: #":\s*"[^"\\]*(?:\\.[^"\\]*)*""#, in: string, color: colors.string, storage: textStorage)
                highlight(pattern: #"\b\d+(\.\d+)?\b"#, in: string, color: colors.number, storage: textStorage)
                highlight(pattern: #"\b(true|false|null)\b"#, in: string, color: colors.keyword, storage: textStorage)
            case .yaml:
                highlight(pattern: #"^[a-zA-Z_][a-zA-Z0-9_]*(?=\s*:)"#, in: string, color: colors.keyword, storage: textStorage)
                highlight(pattern: #""[^"\\]*(?:\\.[^"\\]*)*""#, in: string, color: colors.string, storage: textStorage)
                highlight(pattern: #"'[^']*'"#, in: string, color: colors.string, storage: textStorage)
                highlight(pattern: #"\b\d+(\.\d+)?\b"#, in: string, color: colors.number, storage: textStorage)
                highlight(pattern: #"\b(true|false|null|yes|no)\b"#, in: string, color: colors.keyword, storage: textStorage)
                highlight(pattern: #"#.*"#, in: string, color: colors.comment, storage: textStorage)
            case .markdown:
                highlight(pattern: #"^#{1,6}\s+.*$"#, in: string, color: colors.keyword, storage: textStorage)
                highlight(pattern: #"\*\*[^*]+\*\*"#, in: string, color: colors.type, storage: textStorage)
                highlight(pattern: #"\*[^*]+\*"#, in: string, color: colors.type, storage: textStorage)
                highlight(pattern: #"`[^`]+`"#, in: string, color: colors.string, storage: textStorage)
                highlight(pattern: #"\[([^\]]+)\]\([^\)]+\)"#, in: string, color: colors.call, storage: textStorage)
                highlight(pattern: #"```[\s\S]*?```"#, in: string, color: colors.string, storage: textStorage)
            case .html:
                highlight(pattern: #"</?[a-zA-Z][a-zA-Z0-9]*"#, in: string, color: colors.keyword, storage: textStorage)
                highlight(pattern: #"\b[a-zA-Z-]+(?=\s*=)"#, in: string, color: colors.type, storage: textStorage)
                highlight(pattern: #""[^"]*""#, in: string, color: colors.string, storage: textStorage)
                highlight(pattern: #"'[^']*'"#, in: string, color: colors.string, storage: textStorage)
                highlight(pattern: #"<!--[\s\S]*?-->"#, in: string, color: colors.comment, storage: textStorage)
            case .css:
                highlight(pattern: #"[.#][a-zA-Z_-][a-zA-Z0-9_-]*"#, in: string, color: colors.keyword, storage: textStorage)
                highlight(pattern: #"[a-z-]+(?=\s*:)"#, in: string, color: colors.type, storage: textStorage)
                highlight(pattern: #""[^"]*""#, in: string, color: colors.string, storage: textStorage)
                highlight(pattern: #"'[^']*'"#, in: string, color: colors.string, storage: textStorage)
                highlight(pattern: #"\b\d+(\.\d+)?(px|em|rem|%|vh|vw|s|ms)?\b"#, in: string, color: colors.number, storage: textStorage)
                highlight(pattern: #"#[0-9a-fA-F]{3,8}\b"#, in: string, color: colors.number, storage: textStorage)
                highlight(pattern: #"/\*[\s\S]*?\*/"#, in: string, color: colors.comment, storage: textStorage)
                highlight(pattern: #"//.*"#, in: string, color: colors.comment, storage: textStorage)
            case .sql:
                highlight(pattern: #"'[^']*'"#, in: string, color: colors.string, storage: textStorage)
                highlight(pattern: #"\b\d+(\.\d+)?\b"#, in: string, color: colors.number, storage: textStorage)
                let sqlKeywords = keywordsPattern(for: .sql)
                highlight(pattern: sqlKeywords, in: string, color: colors.keyword, storage: textStorage)
                highlight(pattern: #"\b[A-Z][a-zA-Z0-9_]*\b"#, in: string, color: colors.type, storage: textStorage)
                highlight(pattern: #"\b[a-z][a-zA-Z0-9_]*(?=\()"#, in: string, color: colors.call, storage: textStorage)
                highlight(pattern: #"--.*"#, in: string, color: colors.comment, storage: textStorage)
                highlight(pattern: #"(?s)/\*.*?\*/"#, in: string, color: colors.comment, storage: textStorage)
            case .lua:
                highlight(pattern: #""[^"\\\n]*(\\.[^"\\\n]*)*""#, in: string, color: colors.string, storage: textStorage)
                highlight(pattern: #"'[^'\\\n]*(\\.[^'\\\n]*)*'"#, in: string, color: colors.string, storage: textStorage)
                highlight(pattern: #"\b\d+(\.\d+)?\b"#, in: string, color: colors.number, storage: textStorage)
                let luaKeywords = keywordsPattern(for: .lua)
                highlight(pattern: luaKeywords, in: string, color: colors.keyword, storage: textStorage)
                highlight(pattern: #"\b[A-Z][a-zA-Z0-9_]*\b"#, in: string, color: colors.type, storage: textStorage)
                highlight(pattern: #"\b[a-z][a-zA-Z0-9_]*(?=\()"#, in: string, color: colors.call, storage: textStorage)
                highlight(pattern: #"--.*"#, in: string, color: colors.comment, storage: textStorage)
                highlight(pattern: #"(?s)--\[\[.*?\]\]"#, in: string, color: colors.comment, storage: textStorage)
            case .liquid:
                highlight(pattern: #"</?[a-zA-Z][a-zA-Z0-9]*"#, in: string, color: colors.keyword, storage: textStorage)
                highlight(pattern: #"\b[a-zA-Z-]+(?=\s*=)"#, in: string, color: colors.type, storage: textStorage)
                highlight(pattern: #""[^"]*""#, in: string, color: colors.string, storage: textStorage)
                highlight(pattern: #"'[^']*'"#, in: string, color: colors.string, storage: textStorage)
                highlight(pattern: #"<!--[\s\S]*?-->"#, in: string, color: colors.comment, storage: textStorage)
                highlight(pattern: #"\{%[\s\S]*?%\}"#, in: string, color: colors.type, storage: textStorage)
                highlight(pattern: #"\{\{[\s\S]*?\}\}"#, in: string, color: colors.call, storage: textStorage)
                highlight(pattern: #"\{%[\s\S]*?comment[\s\S]*?endcomment[\s\S]*?%\}"#, in: string, color: colors.comment, storage: textStorage)
            default:
                highlight(pattern: #""[^"\\\n]*(\\.[^"\\\n]*)*""#, in: string, color: colors.string, storage: textStorage)
                if lang == .python || lang == .ruby || lang == .shell {
                    highlight(pattern: #"'[^'\\\n]*(\\.[^'\\\n]*)*'"#, in: string, color: colors.string, storage: textStorage)
                }
                highlight(pattern: #"\b\d+(\.\d+)?\b"#, in: string, color: colors.number, storage: textStorage)
                let keywords = keywordsPattern(for: lang)
                highlight(pattern: keywords, in: string, color: colors.keyword, storage: textStorage)
                highlight(pattern: #"\b[A-Z][a-zA-Z0-9_]*\b"#, in: string, color: colors.type, storage: textStorage)
                if lang == .swift || lang == .python || lang == .javascript {
                    highlight(pattern: #"@[a-zA-Z0-9_]+"#, in: string, color: colors.keyword, storage: textStorage)
                }
                if lang == .rust {
                    highlight(pattern: #"#\[[\w:(,\s)]*\]"#, in: string, color: colors.keyword, storage: textStorage)
                }
                highlight(pattern: #"\b[a-z][a-zA-Z0-9_]*(?=\()"#, in: string, color: colors.call, storage: textStorage)
                if lang == .python || lang == .ruby || lang == .shell {
                    highlight(pattern: #"#.*"#, in: string, color: colors.comment, storage: textStorage)
                } else {
                    highlight(pattern: #"//.*"#, in: string, color: colors.comment, storage: textStorage)
                    highlight(pattern: #"(?s)/\*.*?\*/"#, in: string, color: colors.comment, storage: textStorage)
                }
                if lang == .python {
                    highlight(pattern: #"\"\"\"[\s\S]*?\"\"\""#, in: string, color: colors.string, storage: textStorage)
                    highlight(pattern: #"'''[\s\S]*?'''"#, in: string, color: colors.string, storage: textStorage)
                }
                if lang == .rust {
                    highlight(pattern: #"'[a-z_]+"#, in: string, color: colors.type, storage: textStorage)
                }
            }

            textStorage.endEditing()
        }

        private func highlight(pattern: String, in text: String, color: NSColor, storage: NSTextStorage) {
            let regex: NSRegularExpression
            if let cached = regexCache[pattern] {
                regex = cached
            } else {
                guard let created = try? NSRegularExpression(pattern: pattern, options: []) else { return }
                regexCache[pattern] = created
                regex = created
            }
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
            for match in matches {
                storage.addAttribute(.foregroundColor, value: color, range: match.range)
            }
        }
    }

    struct EditorColors {
        let background: NSColor
        let text: NSColor
        let keyword: NSColor
        let type: NSColor
        let string: NSColor
        let comment: NSColor
        let number: NSColor
        let call: NSColor
    }

    func getEditorColors(for theme: EditorTheme) -> EditorColors {
        switch theme {
        case .dracula:
            return EditorColors(
                background: NSColor(srgbRed: 0.157, green: 0.165, blue: 0.212, alpha: 1.0),
                text: NSColor(srgbRed: 0.973, green: 0.973, blue: 0.949, alpha: 1.0),
                keyword: NSColor(srgbRed: 1.0, green: 0.475, blue: 0.776, alpha: 1.0),
                type: NSColor(srgbRed: 0.545, green: 0.914, blue: 0.992, alpha: 1.0),
                string: NSColor(srgbRed: 0.945, green: 0.980, blue: 0.549, alpha: 1.0),
                comment: NSColor(srgbRed: 0.384, green: 0.447, blue: 0.643, alpha: 1.0),
                number: NSColor(srgbRed: 0.741, green: 0.576, blue: 0.976, alpha: 1.0),
                call: NSColor(srgbRed: 0.314, green: 0.980, blue: 0.482, alpha: 1.0)
            )
        case .cityLights:
            return EditorColors(
                background: NSColor(srgbRed: 0.114, green: 0.145, blue: 0.173, alpha: 1.0),
                text: NSColor(srgbRed: 0.443, green: 0.549, blue: 0.631, alpha: 1.0),
                keyword: NSColor(srgbRed: 0.325, green: 0.604, blue: 0.988, alpha: 1.0),
                type: NSColor(srgbRed: 0.0, green: 0.733, blue: 0.824, alpha: 1.0),
                string: NSColor(srgbRed: 0.545, green: 0.831, blue: 0.612, alpha: 1.0),
                comment: NSColor(srgbRed: 0.255, green: 0.314, blue: 0.369, alpha: 1.0),
                number: NSColor(srgbRed: 0.886, green: 0.494, blue: 0.553, alpha: 1.0),
                call: NSColor(srgbRed: 0.325, green: 0.604, blue: 0.988, alpha: 1.0)
            )
        case .githubLight:
            return EditorColors(
                background: NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
                text: NSColor(srgbRed: 0.141, green: 0.161, blue: 0.180, alpha: 1.0),
                keyword: NSColor(srgbRed: 0.843, green: 0.227, blue: 0.286, alpha: 1.0),
                type: NSColor(srgbRed: 0.435, green: 0.259, blue: 0.757, alpha: 1.0),
                string: NSColor(srgbRed: 0.012, green: 0.184, blue: 0.384, alpha: 1.0),
                comment: NSColor(srgbRed: 0.416, green: 0.451, blue: 0.490, alpha: 1.0),
                number: NSColor(srgbRed: 0.0, green: 0.361, blue: 0.773, alpha: 1.0),
                call: NSColor(srgbRed: 0.435, green: 0.259, blue: 0.757, alpha: 1.0)
            )
        case .catppuccinMocha:
            return EditorColors(
                background: NSColor(srgbRed: 0.118, green: 0.118, blue: 0.180, alpha: 1.0),
                text: NSColor(srgbRed: 0.804, green: 0.839, blue: 0.957, alpha: 1.0),
                keyword: NSColor(srgbRed: 0.796, green: 0.651, blue: 0.969, alpha: 1.0),
                type: NSColor(srgbRed: 0.537, green: 0.706, blue: 0.980, alpha: 1.0),
                string: NSColor(srgbRed: 0.651, green: 0.890, blue: 0.631, alpha: 1.0),
                comment: NSColor(srgbRed: 0.424, green: 0.439, blue: 0.525, alpha: 1.0),
                number: NSColor(srgbRed: 0.980, green: 0.702, blue: 0.529, alpha: 1.0),
                call: NSColor(srgbRed: 0.537, green: 0.706, blue: 0.980, alpha: 1.0)
            )
        case .oneDarkPro:
            return EditorColors(
                background: NSColor(srgbRed: 0.157, green: 0.173, blue: 0.204, alpha: 1.0),
                text: NSColor(srgbRed: 0.671, green: 0.698, blue: 0.749, alpha: 1.0),
                keyword: NSColor(srgbRed: 0.776, green: 0.471, blue: 0.867, alpha: 1.0),
                type: NSColor(srgbRed: 0.898, green: 0.753, blue: 0.482, alpha: 1.0),
                string: NSColor(srgbRed: 0.596, green: 0.765, blue: 0.475, alpha: 1.0),
                comment: NSColor(srgbRed: 0.361, green: 0.388, blue: 0.439, alpha: 1.0),
                number: NSColor(srgbRed: 0.820, green: 0.604, blue: 0.400, alpha: 1.0),
                call: NSColor(srgbRed: 0.380, green: 0.686, blue: 0.937, alpha: 1.0)
            )
        case .tokyoNight:
            return EditorColors(
                background: NSColor(srgbRed: 0.102, green: 0.106, blue: 0.149, alpha: 1.0),
                text: NSColor(srgbRed: 0.663, green: 0.694, blue: 0.839, alpha: 1.0),
                keyword: NSColor(srgbRed: 0.733, green: 0.604, blue: 0.969, alpha: 1.0),
                type: NSColor(srgbRed: 0.165, green: 0.765, blue: 0.871, alpha: 1.0),
                string: NSColor(srgbRed: 0.620, green: 0.808, blue: 0.416, alpha: 1.0),
                comment: NSColor(srgbRed: 0.337, green: 0.373, blue: 0.537, alpha: 1.0),
                number: NSColor(srgbRed: 1.0, green: 0.620, blue: 0.392, alpha: 1.0),
                call: NSColor(srgbRed: 0.478, green: 0.635, blue: 0.969, alpha: 1.0)
            )
        }
    }
}

class LineNumberRulerView: NSRulerView {
    var theme: EditorTheme = .dracula
    init(textView: NSTextView) {
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 35
    }
    required init(coder: NSCoder) { fatalError() }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = clientView as? NSTextView, let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }

        let isLight = !theme.isDark
        let bg = isLight ? NSColor(srgbRed: 0.949, green: 0.949, blue: 0.949, alpha: 1.0) : NSColor.black.withAlphaComponent(0.15)
        bg.set()
        rect.fill()

        let string = textView.string as NSString
        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        var lineNumber = 1
        var index = 0
        while index < charRange.location {
            index = string.lineRange(for: NSRange(location: index, length: 0)).upperBound
            lineNumber += 1
        }

        index = charRange.location
        while index < NSMaxRange(charRange) {
            let lineRange = string.lineRange(for: NSRange(location: index, length: 0))
            let lineGlyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            let lineRect = layoutManager.boundingRect(forGlyphRange: lineGlyphRange, in: textContainer)
            
            let y = lineRect.origin.y + textView.textContainerInset.height - visibleRect.origin.y

            let color = isLight ? NSColor(srgbRed: 0.416, green: 0.451, blue: 0.490, alpha: 0.7) : NSColor.secondaryLabelColor
            let currentFontSize = textView.font?.pointSize ?? 13.0
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: currentFontSize * 0.7, weight: .regular),
                .foregroundColor: color
            ]
            let str = "\(lineNumber)" as NSString
            let size = str.size(withAttributes: attrs)
            
            let x = ruleThickness - size.width - 10
            str.draw(at: NSPoint(x: x, y: y + (lineRect.height - size.height)/2), withAttributes: attrs)

            index = lineRange.upperBound
            lineNumber += 1
        }
    }
}
