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
    var tabSize: Int = 4
    var useTabs: Bool = false
    var autoCloseBrackets: Bool = true
    var autoCloseQuotes: Bool = true
    var letterSpacing: Double = 0.0
    var highlightCurrentLine: Bool = true
    var showRuler: Bool = false
    var rulerColumn: Int = 80
    var bracketPairHighlight: Bool = true
    var showIndentGuides: Bool = false
    var searchQuery: String = ""
    var currentMatchIndex: Int = 0
    var onMatchCountChanged: ((Int) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = ZionTextView(frame: .zero, textContainer: textContainer)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.autoresizingMask = [.width]

        textView.coordinator = context.coordinator
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont(name: fontFamily, size: fontSize)
            ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.usesAdaptiveColorMappingForDarkAppearance = false

        scrollView.documentView = textView

        // Setup Line Numbers
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        let ruler = LineNumberRulerView(textView: textView)
        ruler.theme = theme
        scrollView.verticalRulerView = ruler

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? ZionTextView else { return }

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

        // Editor settings
        textView.editorTabSize = tabSize
        textView.editorUseTabs = useTabs
        textView.editorAutoCloseBrackets = autoCloseBrackets
        textView.editorAutoCloseQuotes = autoCloseQuotes
        textView.editorHighlightCurrentLine = highlightCurrentLine
        textView.showColumnRuler = showRuler
        textView.columnRulerPosition = rulerColumn
        textView.editorBracketPairHighlight = bracketPairHighlight
        textView.editorShowIndentGuides = showIndentGuides

        // Current line highlight color — theme-aware
        textView.currentLineHighlightColor = theme.isLightAppearance
            ? NSColor.black.withAlphaComponent(0.06)
            : NSColor.white.withAlphaComponent(0.04)
        textView.isLightTheme = theme.isLightAppearance

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

        // Apply line spacing and letter spacing
        let range = NSRange(location: 0, length: textView.string.utf16.count)
        if range.length > 0 {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = CGFloat(lineSpacing)
            textView.textStorage?.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
            textView.textStorage?.addAttribute(.kern, value: CGFloat(letterSpacing), range: range)
        }

        // Search highlighting
        let coord2 = context.coordinator
        if searchQuery != coord2.lastSearchQuery {
            coord2.lastSearchQuery = searchQuery
            coord2.updateSearchHighlights(in: textView, query: searchQuery, currentIndex: currentMatchIndex)
            onMatchCountChanged?(coord2.searchMatchRanges.count)
        } else if currentMatchIndex != coord2.lastCurrentMatchIndex {
            coord2.lastCurrentMatchIndex = currentMatchIndex
            coord2.updateCurrentMatchHighlight(in: textView, currentIndex: currentMatchIndex)
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
        var lastSearchQuery: String = ""
        var lastCurrentMatchIndex: Int = 0
        var searchMatchRanges: [NSRange] = []
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

        @MainActor
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? ZionTextView else { return }
            textView.updateBracketMatch()
            textView.needsDisplay = true
        }

        // MARK: - Language Detection

        enum LanguageType {
            case swift, javascript, python, rust, go, ruby, html, css, json, yaml, markdown, shell, cLike, sql, lua, liquid, unknown
        }

        func detectLanguage(from ext: String) -> LanguageType {
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

        enum CommentStyle {
            case line(String)
            case block(String, String)
            case none
        }

        func commentStyle() -> CommentStyle {
            let lang = detectLanguage(from: parent.fileExtension)
            switch lang {
            case .swift, .javascript, .rust, .go, .cLike, .css, .json, .unknown:
                return .line("//")
            case .python, .ruby, .shell, .yaml:
                return .line("#")
            case .sql, .lua:
                return .line("--")
            case .html, .liquid, .markdown:
                return .block("<!-- ", " -->")
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

        // MARK: - Search Highlighting

        private static let searchHighlightKey = NSAttributedString.Key("ZionSearchHighlight")
        private static let searchMatchColor = NSColor.systemYellow.withAlphaComponent(0.35)
        private static let searchCurrentMatchColor = NSColor.systemOrange.withAlphaComponent(0.55)

        @MainActor
        func updateSearchHighlights(in textView: NSTextView, query: String, currentIndex: Int) {
            guard let textStorage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: textStorage.length)

            // Clear previous search highlights
            textStorage.removeAttribute(.backgroundColor, range: fullRange)
            searchMatchRanges = []

            guard !query.isEmpty else { return }

            let escaped = NSRegularExpression.escapedPattern(for: query)
            guard let regex = try? NSRegularExpression(pattern: escaped, options: .caseInsensitive) else { return }
            let matches = regex.matches(in: textView.string, options: [], range: fullRange)

            searchMatchRanges = matches.map { $0.range }

            textStorage.beginEditing()
            for (i, range) in searchMatchRanges.enumerated() {
                let color = (i == currentIndex) ? Self.searchCurrentMatchColor : Self.searchMatchColor
                textStorage.addAttribute(.backgroundColor, value: color, range: range)
            }
            textStorage.endEditing()

            lastCurrentMatchIndex = currentIndex

            // Scroll to current match
            if currentIndex < searchMatchRanges.count {
                textView.scrollRangeToVisible(searchMatchRanges[currentIndex])
            }
        }

        @MainActor
        func updateCurrentMatchHighlight(in textView: NSTextView, currentIndex: Int) {
            guard let textStorage = textView.textStorage, !searchMatchRanges.isEmpty else { return }

            textStorage.beginEditing()
            for (i, range) in searchMatchRanges.enumerated() {
                let color = (i == currentIndex) ? Self.searchCurrentMatchColor : Self.searchMatchColor
                textStorage.addAttribute(.backgroundColor, value: color, range: range)
            }
            textStorage.endEditing()

            if currentIndex < searchMatchRanges.count {
                textView.scrollRangeToVisible(searchMatchRanges[currentIndex])
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

// MARK: - ZionTextView — Custom NSTextView with editor features

class ZionTextView: NSTextView {
    weak var coordinator: SourceCodeEditor.Coordinator?
    var currentLineHighlightColor: NSColor = NSColor.white.withAlphaComponent(0.04)
    var isLightTheme: Bool = false

    // Editor settings
    var editorTabSize: Int = 4
    var editorUseTabs: Bool = false
    var editorAutoCloseBrackets: Bool = true
    var editorAutoCloseQuotes: Bool = true
    var editorHighlightCurrentLine: Bool = true
    var showColumnRuler: Bool = false
    var columnRulerPosition: Int = 80
    var editorBracketPairHighlight: Bool = true
    var editorShowIndentGuides: Bool = false
    var matchingBracketRange: NSRange?

    var indentString: String {
        editorUseTabs ? "\t" : String(repeating: " ", count: editorTabSize)
    }

    private static let autoClosePairs: [Character: Character] = [
        "(": ")", "[": "]", "{": "}",
        "\"": "\"", "'": "'", "`": "`"
    ]

    private static let bracketPairs: [Character: Character] = [
        "(": ")", "[": "]", "{": "}"
    ]
    private static let closingBrackets: [Character: Character] = [
        ")": "(", "]": "[", "}": "{"
    ]

    // MARK: - Background Drawing (current line, ruler, brackets, indent guides)

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let layoutManager = layoutManager, let textContainer = textContainer else { return }

        // Current line highlight
        if editorHighlightCurrentLine && !string.isEmpty {
            let sel = selectedRange()
            let nsString = string as NSString
            let lineRange = nsString.lineRange(for: NSRange(location: sel.location, length: 0))
            let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            var lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            lineRect.origin.x = 0
            lineRect.size.width = bounds.width
            lineRect.origin.y += textContainerOrigin.y

            if lineRect.intersects(rect) {
                currentLineHighlightColor.setFill()
                lineRect.fill()
            }
        }

        // Column ruler
        if showColumnRuler {
            drawColumnRuler(in: rect)
        }

        // Bracket pair highlight
        if editorBracketPairHighlight {
            drawBracketHighlightPair(in: rect)
        }

        // Indent guides
        if editorShowIndentGuides {
            drawIndentGuides(in: rect)
        }
    }

    private func drawColumnRuler(in rect: NSRect) {
        guard let font = self.font else { return }
        let charWidth = NSString("m").size(withAttributes: [.font: font]).width
        let x = textContainerOrigin.x + charWidth * CGFloat(columnRulerPosition)
        guard rect.minX <= x && x <= rect.maxX else { return }

        let color = isLightTheme
            ? NSColor.black.withAlphaComponent(0.08)
            : NSColor.white.withAlphaComponent(0.08)
        color.setStroke()

        let path = NSBezierPath()
        path.move(to: NSPoint(x: x, y: rect.minY))
        path.line(to: NSPoint(x: x, y: rect.maxY))
        path.lineWidth = 1.0
        path.stroke()
    }

    private func drawBracketHighlight(range: NSRange, in rect: NSRect) {
        guard let layoutManager = layoutManager, let textContainer = textContainer else { return }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var bracketRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        bracketRect.origin.y += textContainerOrigin.y
        bracketRect.origin.x += textContainerOrigin.x

        guard bracketRect.intersects(rect) else { return }

        let color = NSColor.systemBlue.withAlphaComponent(0.2)
        color.setFill()
        let highlightRect = bracketRect.insetBy(dx: -1, dy: -1)
        let path = NSBezierPath(roundedRect: highlightRect, xRadius: 2, yRadius: 2)
        path.fill()
    }

    private func drawIndentGuides(in rect: NSRect) {
        guard let layoutManager = layoutManager, let textContainer = textContainer, let font = self.font else { return }
        guard !string.isEmpty else { return }

        let charWidth = NSString(" ").size(withAttributes: [.font: font]).width
        let guideSpacing = charWidth * CGFloat(editorTabSize)
        guard guideSpacing > 0 else { return }

        let color = isLightTheme
            ? NSColor.black.withAlphaComponent(0.06)
            : NSColor.white.withAlphaComponent(0.06)
        color.setStroke()

        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        let nsString = string as NSString
        var index = visibleCharRange.location
        while index < NSMaxRange(visibleCharRange) && index < nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: index, length: 0))
            let lineText = nsString.substring(with: lineRange)

            // Count leading whitespace columns
            var columns = 0
            for ch in lineText {
                if ch == " " { columns += 1 }
                else if ch == "\t" { columns += editorTabSize }
                else { break }
            }

            let lineGlyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            let lineRect = layoutManager.boundingRect(forGlyphRange: lineGlyphRange, in: textContainer)

            // Draw guide at each indent level
            var level = 1
            while CGFloat(level) * guideSpacing < charWidth * CGFloat(columns) {
                let x = textContainerOrigin.x + CGFloat(level) * guideSpacing
                let path = NSBezierPath()
                path.move(to: NSPoint(x: x, y: lineRect.minY + textContainerOrigin.y))
                path.line(to: NSPoint(x: x, y: lineRect.maxY + textContainerOrigin.y))
                path.lineWidth = 0.5
                path.stroke()
                level += 1
            }

            index = NSMaxRange(lineRange)
        }
    }

    // MARK: - Bracket Matching

    func updateBracketMatch() {
        matchingBracketRange = nil
        guard editorBracketPairHighlight else { needsDisplay = true; return }

        let sel = selectedRange()
        let pos = sel.location
        let nsString = string as NSString
        let length = nsString.length
        guard length > 0 else { return }

        // Check char at cursor and before cursor
        let positions = [pos, pos > 0 ? pos - 1 : -1].filter { $0 >= 0 && $0 < length }

        for checkPos in positions {
            let ch = Character(nsString.substring(with: NSRange(location: checkPos, length: 1)))

            if let closing = ZionTextView.bracketPairs[ch] {
                // Opening bracket — scan forward
                if let matchPos = findMatchingBracket(from: checkPos + 1, open: ch, close: closing, forward: true) {
                    // Highlight both brackets
                    drawBothBrackets(checkPos, matchPos)
                    return
                }
            } else if let opening = ZionTextView.closingBrackets[ch] {
                // Closing bracket — scan backward
                if let matchPos = findMatchingBracket(from: checkPos - 1, open: opening, close: ch, forward: false) {
                    drawBothBrackets(matchPos, checkPos)
                    return
                }
            }
        }
        needsDisplay = true
    }

    private func drawBothBrackets(_ pos1: Int, _ pos2: Int) {
        // We draw both brackets — use two passes via drawBackground
        // Store the second bracket for drawBackground; draw both in sequence
        matchingBracketRange = NSRange(location: pos1, length: 1)
        // Store second bracket in a temporary — we need to draw both
        secondBracketRange = NSRange(location: pos2, length: 1)
        needsDisplay = true
    }

    var secondBracketRange: NSRange?

    // Override drawBackground to also draw secondBracketRange
    private func drawBracketHighlightPair(in rect: NSRect) {
        if let range = matchingBracketRange {
            drawBracketHighlight(range: range, in: rect)
        }
        if let range = secondBracketRange {
            drawBracketHighlight(range: range, in: rect)
        }
    }

    private func findMatchingBracket(from start: Int, open: Character, close: Character, forward: Bool) -> Int? {
        let nsString = string as NSString
        let length = nsString.length
        var depth = 1
        var pos = start
        let maxScan = 10_000 // Safety limit

        var scanned = 0
        while pos >= 0 && pos < length && scanned < maxScan {
            let ch = Character(nsString.substring(with: NSRange(location: pos, length: 1)))
            if ch == (forward ? close : open) {
                depth -= 1
                if depth == 0 { return pos }
            } else if ch == (forward ? open : close) {
                depth += 1
            }
            pos += forward ? 1 : -1
            scanned += 1
        }
        return nil
    }

    // MARK: - Key Interception

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])

        switch (event.keyCode, flags) {
        case (126, .option):          // Option+Up: Move line up
            moveLineUp()
            return
        case (125, .option):          // Option+Down: Move line down
            moveLineDown()
            return
        case (125, [.shift, .option]): // Shift+Option+Down: Duplicate line
            duplicateLineDown()
            return
        case (48, []) where !hasMarkedText(): // Tab: Indent
            indentLines()
            return
        case (48, .shift):            // Shift+Tab: Outdent
            outdentLines()
            return
        case (36, []), (76, []):      // Return/Enter: Auto-indent
            autoIndentNewLine()
            return
        default:
            break
        }

        // Cmd+/: Toggle comment (use charactersIgnoringModifiers for keyboard layout independence)
        if flags == .command, event.charactersIgnoringModifiers == "/" {
            toggleComment()
            return
        }

        // Auto-closing brackets/quotes
        if let chars = event.characters, chars.count == 1, !flags.contains(.command), !flags.contains(.control) {
            let char = chars.first!
            if handleAutoClose(char) {
                return
            }
        }

        super.keyDown(with: event)
    }

    // MARK: - Delete Backward (auto-close pair removal)

    override func deleteBackward(_ sender: Any?) {
        let sel = selectedRange()
        if sel.length == 0 && sel.location > 0 && sel.location < (string as NSString).length {
            let nsString = string as NSString
            let prev = nsString.substring(with: NSRange(location: sel.location - 1, length: 1))
            let next = nsString.substring(with: NSRange(location: sel.location, length: 1))
            let pairs: [String: String] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'", "`": "`"]
            if let closing = pairs[prev], closing == next {
                let deleteRange = NSRange(location: sel.location - 1, length: 2)
                if shouldChangeText(in: deleteRange, replacementString: "") {
                    textStorage?.replaceCharacters(in: deleteRange, with: "")
                    didChangeText()
                    setSelectedRange(NSRange(location: sel.location - 1, length: 0))
                    return
                }
            }
        }
        super.deleteBackward(sender)
    }

    // MARK: - Move Line Up

    private func moveLineUp() {
        let nsString = string as NSString
        let cursorPos = selectedRange().location
        let currentLineRange = nsString.lineRange(for: NSRange(location: cursorPos, length: 0))
        guard currentLineRange.location > 0 else { return }

        let prevLineRange = nsString.lineRange(for: NSRange(location: currentLineRange.location - 1, length: 0))
        var currentLine = nsString.substring(with: currentLineRange)
        var prevLine = nsString.substring(with: prevLineRange)

        // Handle last line (no trailing newline)
        if !currentLine.hasSuffix("\n") {
            currentLine += "\n"
            prevLine = String(prevLine.dropLast())
        }

        let combinedRange = NSRange(location: prevLineRange.location, length: prevLineRange.length + currentLineRange.length)
        let replacement = currentLine + prevLine
        let offsetInLine = cursorPos - currentLineRange.location
        let maxOffset = max(0, (currentLine as NSString).length - 1)
        let newCursorPos = prevLineRange.location + min(offsetInLine, maxOffset)

        if shouldChangeText(in: combinedRange, replacementString: replacement) {
            textStorage?.replaceCharacters(in: combinedRange, with: replacement)
            didChangeText()
            setSelectedRange(NSRange(location: newCursorPos, length: 0))
        }
    }

    // MARK: - Move Line Down

    private func moveLineDown() {
        let nsString = string as NSString
        let cursorPos = selectedRange().location
        let currentLineRange = nsString.lineRange(for: NSRange(location: cursorPos, length: 0))
        let endOfCurrent = NSMaxRange(currentLineRange)
        guard endOfCurrent < nsString.length else { return }

        let nextLineRange = nsString.lineRange(for: NSRange(location: endOfCurrent, length: 0))
        var currentLine = nsString.substring(with: currentLineRange)
        var nextLine = nsString.substring(with: nextLineRange)

        // Handle last line (no trailing newline on the next line)
        if !nextLine.hasSuffix("\n") {
            nextLine += "\n"
            currentLine = String(currentLine.dropLast())
        }

        let combinedRange = NSRange(location: currentLineRange.location, length: currentLineRange.length + nextLineRange.length)
        let replacement = nextLine + currentLine
        let offsetInLine = cursorPos - currentLineRange.location
        let newCursorPos = currentLineRange.location + (nextLine as NSString).length + min(offsetInLine, (currentLine as NSString).length)

        if shouldChangeText(in: combinedRange, replacementString: replacement) {
            textStorage?.replaceCharacters(in: combinedRange, with: replacement)
            didChangeText()
            setSelectedRange(NSRange(location: newCursorPos, length: 0))
        }
    }

    // MARK: - Duplicate Line Down

    private func duplicateLineDown() {
        let nsString = string as NSString
        let cursorPos = selectedRange().location
        let currentLineRange = nsString.lineRange(for: NSRange(location: cursorPos, length: 0))
        let currentLine = nsString.substring(with: currentLineRange)
        let insertPos = NSMaxRange(currentLineRange)
        let offsetInLine = cursorPos - currentLineRange.location

        var insertion: String
        var newCursorPos: Int
        if currentLine.hasSuffix("\n") {
            insertion = currentLine
            newCursorPos = insertPos + offsetInLine
        } else {
            // Last line — prepend newline
            insertion = "\n" + currentLine
            newCursorPos = insertPos + 1 + offsetInLine
        }

        if shouldChangeText(in: NSRange(location: insertPos, length: 0), replacementString: insertion) {
            textStorage?.replaceCharacters(in: NSRange(location: insertPos, length: 0), with: insertion)
            didChangeText()
            setSelectedRange(NSRange(location: newCursorPos, length: 0))
        }
    }

    // MARK: - Indent / Outdent

    private func indentLines() {
        let nsString = string as NSString
        let sel = selectedRange()
        let indent = indentString

        if sel.length == 0 {
            insertText(indent, replacementRange: sel)
            return
        }

        let lineRange = nsString.lineRange(for: sel)
        let text = nsString.substring(with: lineRange)
        let lines = text.components(separatedBy: "\n")
        let indented = lines.enumerated().map { index, line in
            if index == lines.count - 1 && line.isEmpty { return line }
            return indent + line
        }.joined(separator: "\n")

        if shouldChangeText(in: lineRange, replacementString: indented) {
            textStorage?.replaceCharacters(in: lineRange, with: indented)
            didChangeText()
            setSelectedRange(NSRange(location: lineRange.location, length: (indented as NSString).length))
        }
    }

    private func outdentLines() {
        let nsString = string as NSString
        let sel = selectedRange()
        let lineRange = nsString.lineRange(for: sel)
        let text = nsString.substring(with: lineRange)
        let lines = text.components(separatedBy: "\n")
        let tabSize = editorTabSize
        let outdented = lines.enumerated().map { index, line in
            if index == lines.count - 1 && line.isEmpty { return line }
            var removed = 0
            var result = line
            while removed < tabSize && result.hasPrefix(" ") {
                result = String(result.dropFirst())
                removed += 1
            }
            if removed == 0 && result.hasPrefix("\t") {
                result = String(result.dropFirst())
            }
            return result
        }.joined(separator: "\n")

        if shouldChangeText(in: lineRange, replacementString: outdented) {
            textStorage?.replaceCharacters(in: lineRange, with: outdented)
            didChangeText()
            setSelectedRange(NSRange(location: lineRange.location, length: (outdented as NSString).length))
        }
    }

    // MARK: - Toggle Comment (Cmd+/)

    private func toggleComment() {
        guard let coordinator = coordinator else { return }
        let style = coordinator.commentStyle()

        let nsString = string as NSString
        let sel = selectedRange()
        let lineRange = nsString.lineRange(for: sel)
        let text = nsString.substring(with: lineRange)
        let lines = text.components(separatedBy: "\n")

        let toggled: String
        switch style {
        case .none:
            return

        case .line(let prefix):
            let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let allCommented = !nonEmptyLines.isEmpty && nonEmptyLines.allSatisfy {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix)
            }

            toggled = lines.map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { return line }

                if allCommented {
                    let leading = line.prefix(while: { $0 == " " || $0 == "\t" })
                    let rest = String(line.dropFirst(leading.count))
                    if rest.hasPrefix(prefix + " ") {
                        return String(leading) + String(rest.dropFirst(prefix.count + 1))
                    } else if rest.hasPrefix(prefix) {
                        return String(leading) + String(rest.dropFirst(prefix.count))
                    }
                    return line
                } else {
                    let leading = line.prefix(while: { $0 == " " || $0 == "\t" })
                    let rest = String(line.dropFirst(leading.count))
                    return String(leading) + prefix + " " + rest
                }
            }.joined(separator: "\n")

        case .block(let open, let close):
            let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let allCommented = !nonEmptyLines.isEmpty && nonEmptyLines.allSatisfy {
                let t = $0.trimmingCharacters(in: .whitespaces)
                return t.hasPrefix(open) && t.hasSuffix(close)
            }

            toggled = lines.map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { return line }

                if allCommented {
                    let leading = line.prefix(while: { $0 == " " || $0 == "\t" })
                    var rest = String(line.dropFirst(leading.count))
                    if rest.hasPrefix(open) {
                        rest = String(rest.dropFirst(open.count))
                    }
                    if rest.hasSuffix(close) {
                        rest = String(rest.dropLast(close.count))
                    }
                    return String(leading) + rest
                } else {
                    let leading = line.prefix(while: { $0 == " " || $0 == "\t" })
                    let rest = String(line.dropFirst(leading.count))
                    return String(leading) + open + rest + close
                }
            }.joined(separator: "\n")
        }

        if shouldChangeText(in: lineRange, replacementString: toggled) {
            textStorage?.replaceCharacters(in: lineRange, with: toggled)
            didChangeText()
            setSelectedRange(NSRange(location: lineRange.location, length: (toggled as NSString).length))
        }
    }

    // MARK: - Auto-close Brackets/Quotes

    private func handleAutoClose(_ char: Character) -> Bool {
        let sel = selectedRange()
        let pos = sel.location
        let nsString = string as NSString
        let closers: Set<Character> = [")", "]", "}"]
        let brackets: Set<Character> = ["(", "[", "{"]
        let quotes: Set<Character> = ["\"", "'", "`"]

        // Check if this character type is enabled
        let isBracketChar = brackets.contains(char) || closers.contains(char)
        let isQuoteChar = quotes.contains(char)
        if isBracketChar && !editorAutoCloseBrackets { return false }
        if isQuoteChar && !editorAutoCloseQuotes { return false }

        // Skip over closing bracket if next char matches
        if closers.contains(char) && sel.length == 0 && pos < nsString.length {
            let nextChar = nsString.substring(with: NSRange(location: pos, length: 1))
            if nextChar == String(char) {
                setSelectedRange(NSRange(location: pos + 1, length: 0))
                return true
            }
        }

        // Skip over closing quote if next char matches
        if quotes.contains(char) && sel.length == 0 && pos < nsString.length {
            let nextChar = nsString.substring(with: NSRange(location: pos, length: 1))
            if nextChar == String(char) {
                setSelectedRange(NSRange(location: pos + 1, length: 0))
                return true
            }
        }

        // Auto-insert closing pair
        guard let closer = ZionTextView.autoClosePairs[char] else { return false }

        // For quotes, only auto-close when next char is whitespace, EOL, or closing bracket
        if quotes.contains(char) && pos < nsString.length {
            let nextChar = Character(nsString.substring(with: NSRange(location: pos, length: 1)))
            if !nextChar.isWhitespace && !closers.contains(nextChar) && nextChar != "\n" {
                return false
            }
        }

        if sel.length > 0 {
            // Wrap selection with pair
            let selectedText = nsString.substring(with: sel)
            let wrapped = String(char) + selectedText + String(closer)
            if shouldChangeText(in: sel, replacementString: wrapped) {
                textStorage?.replaceCharacters(in: sel, with: wrapped)
                didChangeText()
                setSelectedRange(NSRange(location: sel.location + 1, length: sel.length))
                return true
            }
        } else {
            let pair = String(char) + String(closer)
            if shouldChangeText(in: NSRange(location: pos, length: 0), replacementString: pair) {
                textStorage?.replaceCharacters(in: NSRange(location: pos, length: 0), with: pair)
                didChangeText()
                setSelectedRange(NSRange(location: pos + 1, length: 0))
                return true
            }
        }
        return false
    }

    // MARK: - Auto-indent on Enter

    private func autoIndentNewLine() {
        let nsString = string as NSString
        let sel = selectedRange()
        let pos = sel.location
        let currentLineRange = nsString.lineRange(for: NSRange(location: pos, length: 0))
        let textBeforeCursor = nsString.substring(with: NSRange(location: currentLineRange.location, length: pos - currentLineRange.location))

        let leadingWhitespace = String(textBeforeCursor.prefix(while: { $0 == " " || $0 == "\t" }))
        let trimmedBefore = textBeforeCursor.trimmingCharacters(in: .whitespaces)
        let extraIndent = (trimmedBefore.hasSuffix("{") || trimmedBefore.hasSuffix(":") || trimmedBefore.hasSuffix("(")) ? indentString : ""

        let insertion = "\n" + leadingWhitespace + extraIndent
        insertText(insertion, replacementRange: sel)
    }
}

// MARK: - Line Number Ruler

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
