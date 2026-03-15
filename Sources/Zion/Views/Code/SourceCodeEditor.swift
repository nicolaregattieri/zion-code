import AppKit
import SwiftUI

struct SourceCodeEditor: NSViewRepresentable {
    @Binding var text: String
    var theme: EditorTheme
    var fontSize: Double = 13.0
    var fontFamily: String = "SF Mono"
    var lineSpacing: Double = 4.0
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
    var searchScrollRequestID: Int = 0
    var onMatchCountChanged: ((Int) -> Void)?
    var goToLine: Int = 0
    var goToLineRequestID: Int = 0
    var focusRequestID: Int = 0
    var currentFilePath: String? = nil
    var onRequestDefinition: ((EditorSymbolQuery) -> Void)?
    var onRequestReferences: ((EditorSymbolQuery) -> Void)?
    var onFindSeedFromMultiSelect: ((String) -> Void)?
    var onToggleFindUI: (() -> Void)?
    var onFindNextShortcut: (() -> Void)?
    var onFindPreviousShortcut: (() -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = !isLineWrappingEnabled
        scrollView.drawsBackground = true

        let textView = ZionTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.drawsBackground = true
        textView.usesAdaptiveColorMappingForDarkAppearance = false
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.delegate = context.coordinator
        textView.string = text
        ZionTextView.activeTextViewReference.value = textView
        context.coordinator.installedTextView = textView

        textView.coordinator = context.coordinator
        textView.currentFilePath = currentFilePath
        textView.onRequestDefinition = onRequestDefinition
        textView.onRequestReferences = onRequestReferences
        textView.onFindSeedFromMultiSelect = onFindSeedFromMultiSelect
        textView.onToggleFindUI = onToggleFindUI
        textView.onFindNextShortcut = onFindNextShortcut
        textView.onFindPreviousShortcut = onFindPreviousShortcut

        scrollView.documentView = textView

        let ruler = LineNumberRulerView(textView: textView)
        scrollView.hasVerticalRuler = true
        scrollView.verticalRulerView = ruler
        scrollView.rulersVisible = true

        let colors = getEditorColors(for: theme)
        textView.backgroundColor = colors.background
        scrollView.backgroundColor = colors.background
        context.coordinator.applyHighlighting(to: textView, colors: colors)

        context.coordinator.lastHighlightedText = text
        context.coordinator.lastHighlightedTheme = theme
        context.coordinator.lastHighlightedExtension = fileExtension
        context.coordinator.lastActiveFileID = activeFileID

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = isLineWrappingEnabled
            textContainer.containerSize = isLineWrappingEnabled
                ? NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
                : NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? ZionTextView else { return }

        context.coordinator.parent = self

        let colors = getEditorColors(for: theme)
        textView.backgroundColor = colors.background
        nsView.backgroundColor = colors.background
        textView.drawsBackground = true
        let isLight = theme.isLightAppearance
        textView.isLightTheme = isLight
        textView.currentLineHighlightColor = isLight
            ? NSColor.black.withAlphaComponent(0.04)
            : NSColor.white.withAlphaComponent(0.04)

        if let ruler = nsView.verticalRulerView as? LineNumberRulerView {
            ruler.theme = theme
            ruler.needsDisplay = true
        }

        textView.currentFilePath = currentFilePath
        textView.onRequestDefinition = onRequestDefinition
        textView.onRequestReferences = onRequestReferences
        textView.onFindSeedFromMultiSelect = onFindSeedFromMultiSelect
        textView.onToggleFindUI = onToggleFindUI
        textView.onFindNextShortcut = onFindNextShortcut
        textView.onFindPreviousShortcut = onFindPreviousShortcut

        textView.editorTabSize = tabSize
        textView.editorUseTabs = useTabs
        textView.editorAutoCloseBrackets = autoCloseBrackets
        textView.editorAutoCloseQuotes = autoCloseQuotes
        textView.editorHighlightCurrentLine = highlightCurrentLine
        textView.showColumnRuler = showRuler
        textView.columnRulerPosition = rulerColumn
        textView.editorBracketPairHighlight = bracketPairHighlight
        textView.editorShowIndentGuides = showIndentGuides

        let coord = context.coordinator
        let fileChanged = activeFileID != coord.lastActiveFileID
        if fileChanged { coord.lastActiveFileID = activeFileID }

        // Update font
        let needsFontUpdate = coord.cachedFontSize != fontSize || coord.cachedFontFamily != fontFamily
        if needsFontUpdate {
            let font: NSFont
            if let custom = NSFont(name: fontFamily, size: CGFloat(fontSize)) {
                font = custom
            } else {
                font = NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
            }
            textView.font = font
            coord.cachedFont = font
            coord.cachedFontSize = fontSize
            coord.cachedFontFamily = fontFamily
            if let ruler = nsView.verticalRulerView as? LineNumberRulerView {
                ruler.needsDisplay = true
            }
        }

        // Update text
        if text != textView.string || fileChanged {
            let sel = textView.selectedRange()
            textView.string = text
            let clampedLoc = min(sel.location, (text as NSString).length)
            let clampedLen = min(sel.length, max(0, (text as NSString).length - clampedLoc))
            textView.setSelectedRange(NSRange(location: clampedLoc, length: clampedLen))
        }

        // Re-highlight if needed
        let needsHighlight = text != coord.lastHighlightedText ||
            theme != coord.lastHighlightedTheme ||
            fileExtension != coord.lastHighlightedExtension ||
            fileChanged
        if needsHighlight {
            coord.applyHighlighting(to: textView, colors: colors)
            coord.lastHighlightedText = text
            coord.lastHighlightedTheme = theme
            coord.lastHighlightedExtension = fileExtension
        }

        // Line spacing
        if lineSpacing != coord.lastLineSpacing || fileChanged {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = CGFloat(lineSpacing)
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            if fullRange.length > 0 {
                textView.textStorage?.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
            }
            coord.lastLineSpacing = lineSpacing
        }

        // Letter spacing
        if letterSpacing != coord.lastLetterSpacing || fileChanged {
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            if fullRange.length > 0 {
                textView.textStorage?.addAttribute(.kern, value: CGFloat(letterSpacing), range: fullRange)
            }
            coord.lastLetterSpacing = letterSpacing
        }

        // Line wrapping
        let contentWidth = nsView.contentSize.width
        let wrappingChanged = isLineWrappingEnabled != coord.lastLineWrappingEnabled
        let widthChanged = abs(contentWidth - (coord.lastWrappedWidth ?? 0)) > 1.0
        if wrappingChanged || (isLineWrappingEnabled && widthChanged) {
            coord.applyLineWrapping(enabled: isLineWrappingEnabled, width: contentWidth, in: nsView, textView: textView)
            coord.lastLineWrappingEnabled = isLineWrappingEnabled
            coord.lastWrappedWidth = contentWidth
        }

        // Search highlights
        let searchChanged = searchQuery != coord.lastSearchQuery || text != coord.lastSearchText || fileChanged
        if searchChanged {
            coord.updateSearchHighlights(in: textView, query: searchQuery, currentIndex: currentMatchIndex)
            coord.lastSearchQuery = searchQuery
            coord.lastSearchText = text
            coord.lastCurrentMatchIndex = currentMatchIndex
            onMatchCountChanged?(coord.searchMatchRanges.count)
        } else if currentMatchIndex != coord.lastCurrentMatchIndex || searchScrollRequestID != coord.lastSearchScrollRequestID {
            coord.updateCurrentMatchHighlight(in: textView, currentIndex: currentMatchIndex)
            coord.lastCurrentMatchIndex = currentMatchIndex
        }

        coord.lastSearchScrollRequestID = searchScrollRequestID

        // Go to line
        if goToLine != coord.lastGoToLine || goToLineRequestID != coord.lastGoToLineRequestID {
            if goToLine > 0 {
                coord.scrollToLine(goToLine, in: textView)
            }
            coord.lastGoToLine = goToLine
            coord.lastGoToLineRequestID = goToLineRequestID
        }

        // Focus request
        if focusRequestID != coord.lastFocusRequestID {
            coord.lastFocusRequestID = focusRequestID
            DispatchQueue.main.async {
                if let window = textView.window {
                    window.makeFirstResponder(textView)
                }
            }
        }

        textView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SourceCodeEditor
        weak var installedTextView: NSTextView?
        var lastActiveFileID: String?
        var lastHighlightedText: String?
        var lastHighlightedTheme: EditorTheme?
        var lastHighlightedExtension: String?
        var regexCache: [String: NSRegularExpression] = [:]
        var cachedFont: NSFont?
        var cachedFontSize: Double?
        var cachedFontFamily: String?
        var cachedColors: SourceCodeEditor.EditorColors?
        var cachedColorsTheme: EditorTheme?
        var lastSearchQuery: String = ""
        var lastSearchText: String = ""
        var lastCurrentMatchIndex: Int = 0
        var lastSearchScrollRequestID: Int = 0
        var searchMatchRanges: [NSRange] = []
        var lastLineWrappingEnabled: Bool?
        var lastWrappedWidth: CGFloat?
        var lastGoToLine: Int = 0
        var lastGoToLineRequestID: Int = 0
        var lastFocusRequestID: Int = -1
        var lastLineSpacing: Double?
        var lastLetterSpacing: Double?
        private var highlightDebounceTask: DispatchWorkItem?
        init(_ parent: SourceCodeEditor) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleFormatCodeFile(_:)),
                name: .formatCodeFile,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self, name: .formatCodeFile, object: nil)
        }

        @MainActor @objc private func handleFormatCodeFile(_ notification: Notification) {
            guard let textView = installedTextView,
                  let formatted = notification.userInfo?["formatted"] as? String else { return }
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            if textView.shouldChangeText(in: fullRange, replacementString: formatted) {
                textView.replaceCharacters(in: fullRange, with: formatted)
                textView.didChangeText()
            }
        }

        @MainActor
        func scrollToLine(_ lineNumber: Int, in textView: NSTextView) {
            let string = textView.string
            guard !string.isEmpty else { return }
            var currentLine = 1
            for (i, char) in string.enumerated() {
                if currentLine == lineNumber {
                    let nsLocation = i
                    let range = NSRange(location: nsLocation, length: 0)
                    textView.setSelectedRange(range)
                    textView.scrollRangeToVisible(range)
                    return
                }
                if char == "\n" {
                    currentLine += 1
                }
            }
            // If lineNumber exceeds total lines, go to last line
            if let lastNewline = string.lastIndex(of: "\n") {
                let nsLocation = string.distance(from: string.startIndex, to: string.index(after: lastNewline))
                textView.setSelectedRange(NSRange(location: nsLocation, length: 0))
                textView.scrollRangeToVisible(NSRange(location: nsLocation, length: 0))
            }
        }

        @MainActor
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if parent.text != textView.string {
                parent.text = textView.string
            }
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
            textView.needsDisplay = true
        }

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
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = CGFloat(parent.lineSpacing)

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
        func updateSearchHighlights(in textView: NSTextView, query: String, currentIndex: Int, scrollToCurrentMatch: Bool = true) {
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
}

// MARK: - ZionTextView — Custom NSTextView with editor features

class ZionTextView: NSTextView {
    final class WeakReference {
        weak var value: ZionTextView?
    }

    static let activeTextViewReference = WeakReference()
    weak var coordinator: SourceCodeEditor.Coordinator?
    var currentLineHighlightColor: NSColor = NSColor.white.withAlphaComponent(0.04)
    var isLightTheme: Bool = false
    var currentFilePath: String?
    var onRequestDefinition: ((EditorSymbolQuery) -> Void)?
    var onRequestReferences: ((EditorSymbolQuery) -> Void)?
    var onFindSeedFromMultiSelect: ((String) -> Void)?
    var onToggleFindUI: (() -> Void)?
    var onFindNextShortcut: (() -> Void)?
    var onFindPreviousShortcut: (() -> Void)?

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
    var secondBracketRange: NSRange?

    var indentString: String {
        editorUseTabs ? "\t" : String(repeating: " ", count: editorTabSize)
    }

    static let autoClosePairs: [Character: Character] = [
        "(": ")", "[": "]", "{": "}",
        "\"": "\"", "'": "'", "`": "`"
    ]

    static let bracketPairs: [Character: Character] = [
        "(": ")", "[": "]", "{": "}"
    ]
    static let closingBrackets: [Character: Character] = [
        ")": "(", "]": "[", "}": "{"
    ]

    // MARK: - Background Drawing

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
                // Opening bracket -- scan forward
                if let matchPos = findMatchingBracket(from: checkPos + 1, open: ch, close: closing, forward: true) {
                    drawBothBrackets(checkPos, matchPos)
                    return
                }
            } else if let opening = ZionTextView.closingBrackets[ch] {
                // Closing bracket -- scan backward
                if let matchPos = findMatchingBracket(from: checkPos - 1, open: opening, close: ch, forward: false) {
                    drawBothBrackets(matchPos, checkPos)
                    return
                }
            }
        }
        needsDisplay = true
    }

    private func drawBothBrackets(_ pos1: Int, _ pos2: Int) {
        matchingBracketRange = NSRange(location: pos1, length: 1)
        secondBracketRange = NSRange(location: pos2, length: 1)
        needsDisplay = true
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
}
