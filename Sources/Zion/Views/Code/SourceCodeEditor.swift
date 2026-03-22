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
    var isEditorVisible: Bool = true

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

        let defaultPS = NSMutableParagraphStyle()
        defaultPS.tabStops = []
        defaultPS.defaultTabInterval = context.coordinator.tabStopInterval(for: textView, tabSize: tabSize)
        textView.defaultParagraphStyle = defaultPS

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

        guard isEditorVisible else { return }

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

        // Line spacing + tab stops
        let tabSizeChanged = tabSize != coord.lastTabSize
        if lineSpacing != coord.lastLineSpacing || tabSizeChanged || needsFontUpdate || fileChanged {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = CGFloat(lineSpacing)
            paragraphStyle.tabStops = []
            paragraphStyle.defaultTabInterval = coord.tabStopInterval(for: textView, tabSize: tabSize)
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            if fullRange.length > 0 {
                textView.textStorage?.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
            }
            textView.defaultParagraphStyle = paragraphStyle
            coord.lastLineSpacing = lineSpacing
            coord.lastTabSize = tabSize
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

        // Scroll to cursor after all attribute changes (highlighting resets scroll position)
        if coord.needsScrollToCursor {
            coord.needsScrollToCursor = false
            textView.scrollRangeToVisible(textView.selectedRange())
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
        var lastTabSize: Int?
        var highlightDebounceTask: DispatchWorkItem?
        var needsScrollToCursor: Bool = false

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

        // MARK: - Language Types

        enum LanguageType {
            case swift, javascript, python, rust, go, ruby, html, css, json, yaml, markdown, shell, cLike, sql, lua, liquid, unknown
        }

        enum CommentStyle {
            case line(String)
            case block(String, String)
            case none
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
