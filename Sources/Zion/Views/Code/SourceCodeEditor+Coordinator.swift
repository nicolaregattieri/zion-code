import AppKit
import SwiftUI

extension SourceCodeEditor.Coordinator {

    // MARK: - Tab Stop

    @MainActor func tabStopInterval(for textView: NSTextView, tabSize: Int) -> CGFloat {
        let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let charWidth = NSString(" ").size(withAttributes: [.font: font]).width
        return charWidth * CGFloat(tabSize)
    }

    // MARK: - Format Code File

    @MainActor @objc func handleFormatCodeFile(_ notification: Notification) {
        guard let textView = installedTextView,
              let formatted = notification.userInfo?["formatted"] as? String else { return }
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        if textView.shouldChangeText(in: fullRange, replacementString: formatted) {
            textView.replaceCharacters(in: fullRange, with: formatted)
            textView.didChangeText()
        }
    }

    // MARK: - Scroll to Line

    @MainActor
    func scrollToLine(_ lineNumber: Int, in textView: NSTextView) {
        let nsString = textView.string as NSString
        let totalLength = nsString.length
        guard totalLength > 0, lineNumber > 0 else { return }
        var currentLine = 1
        var pos = 0
        while pos < totalLength && currentLine < lineNumber {
            let range = nsString.lineRange(for: NSRange(location: pos, length: 0))
            pos = range.upperBound
            currentLine += 1
        }
        let location = min(pos, totalLength)
        let range = NSRange(location: location, length: 0)
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
    }

    // MARK: - Text Change Handling

    @MainActor
    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        if parent.text != textView.string {
            parent.text = textView.string
        }
        needsScrollToCursor = true
        textView.enclosingScrollView?.verticalRulerView?.needsDisplay = true

        highlightDebounceTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let colors = self.parent.getEditorColors(for: self.parent.theme)
            self.applyHighlighting(to: textView, colors: colors)
            self.lastHighlightedText = textView.string
            self.lastHighlightedTheme = self.parent.theme
            self.lastHighlightedExtension = self.parent.fileExtension
        }
        highlightDebounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: task)
    }

    @MainActor
    func textViewDidChangeSelection(_ notification: Notification) {
        guard let textView = notification.object as? ZionTextView else { return }
        textView.updateBracketMatch()
        textView.debounceOccurrenceHighlight()
        textView.needsDisplay = true
    }

    // MARK: - Line Wrapping

    @MainActor
    func applyLineWrapping(enabled: Bool, width: CGFloat, in scrollView: NSScrollView, textView: NSTextView) {
        guard let textContainer = textView.textContainer else { return }

        if enabled {
            let targetWidth = max(width, 1)
            scrollView.hasHorizontalScroller = false
            textView.isHorizontallyResizable = false
            textContainer.widthTracksTextView = true
            textContainer.containerSize = NSSize(width: targetWidth, height: CGFloat.greatestFiniteMagnitude)
            textView.minSize = NSSize(width: 0, height: 0)
            textView.maxSize = NSSize(width: targetWidth, height: CGFloat.greatestFiniteMagnitude)
            if abs(textView.frame.width - targetWidth) > 0.5 {
                textView.setFrameSize(NSSize(width: targetWidth, height: textView.frame.height))
            }
        } else {
            scrollView.hasHorizontalScroller = true
            textView.isHorizontallyResizable = true
            textContainer.widthTracksTextView = false
            textContainer.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }

        textView.layoutManager?.ensureLayout(for: textContainer)
        textView.needsDisplay = true
    }

    // MARK: - Language Detection

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

    func keywordsPattern(for lang: LanguageType) -> String {
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

    // MARK: - Syntax Highlighting

    @MainActor
    func applyHighlighting(to textView: NSTextView, colors: SourceCodeEditor.EditorColors) {
        let string = textView.string
        let length = string.utf16.count
        guard length > 0, let textStorage = textView.textStorage else { return }
        let range = NSRange(location: 0, length: length)
        let lang = detectLanguage(from: parent.fileExtension)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = CGFloat(parent.lineSpacing)
        let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let charWidth = NSString(" ").size(withAttributes: [.font: font]).width
        paragraphStyle.tabStops = []
        paragraphStyle.defaultTabInterval = charWidth * CGFloat(parent.tabSize)

        textStorage.beginEditing()

        // 1. Reset all attributes
        textStorage.setAttributes([
            .foregroundColor: colors.text,
            .font: textView.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .paragraphStyle: paragraphStyle,
            .kern: CGFloat(parent.letterSpacing)
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
            highlight(
                pattern: #"\{%-?\s*comment\s*-?%\}[\s\S]*?\{%-?\s*endcomment\s*-?%\}"#,
                in: string,
                color: colors.comment,
                storage: textStorage
            )
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

    func highlight(pattern: String, in text: String, color: NSColor, storage: NSTextStorage) {
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

    static let searchHighlightKey = NSAttributedString.Key("ZionSearchHighlight")
    static let searchMatchColor = NSColor.systemYellow.withAlphaComponent(0.35)
    static let searchCurrentMatchColor = NSColor.systemOrange.withAlphaComponent(0.55)

    @MainActor
    func updateSearchHighlights(in textView: NSTextView, query: String, currentIndex: Int, scrollToCurrentMatch: Bool = true) {
        guard let textStorage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)

        // Clear previous search highlights
        textStorage.removeAttribute(.backgroundColor, range: fullRange)
        searchMatchRanges = []

        guard !query.isEmpty else { return }

        guard let regex = EditorHelpers.buildSearchRegex(
            query: query,
            matchCase: parent.searchMatchCase,
            isRegex: parent.searchRegex,
            wholeWord: parent.searchWholeWord
        ) else { return }
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
        if scrollToCurrentMatch, currentIndex < searchMatchRanges.count {
            textView.scrollRangeToVisible(searchMatchRanges[currentIndex])
        }
    }

    @MainActor
    func updateCurrentMatchHighlight(in textView: NSTextView, currentIndex: Int, scrollToCurrentMatch: Bool = true) {
        guard let textStorage = textView.textStorage, !searchMatchRanges.isEmpty else { return }
        let previousIndex = lastCurrentMatchIndex

        textStorage.beginEditing()
        // Revert previous match to normal highlight
        if previousIndex < searchMatchRanges.count {
            textStorage.addAttribute(.backgroundColor, value: Self.searchMatchColor, range: searchMatchRanges[previousIndex])
        }
        // Highlight new current match
        if currentIndex < searchMatchRanges.count {
            textStorage.addAttribute(.backgroundColor, value: Self.searchCurrentMatchColor, range: searchMatchRanges[currentIndex])
        }
        textStorage.endEditing()

        if scrollToCurrentMatch, currentIndex < searchMatchRanges.count {
            textView.scrollRangeToVisible(searchMatchRanges[currentIndex])
        }

        // Keep navigation state in sync so previous/next does not accumulate "current" highlight.
        lastCurrentMatchIndex = currentIndex
    }
}
