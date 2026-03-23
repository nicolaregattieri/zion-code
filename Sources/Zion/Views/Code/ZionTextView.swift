import AppKit

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
    var editorRenderWhitespace: String = "none"
    var matchingBracketRange: NSRange?
    var secondBracketRange: NSRange?

    // Occurrence highlight
    var occurrenceHighlightRanges: [NSRange] = []
    private var occurrenceDebounceTask: DispatchWorkItem?

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

        // Occurrence highlight
        if !occurrenceHighlightRanges.isEmpty {
            drawOccurrenceHighlights(in: rect)
        }

        // Whitespace glyphs
        if editorRenderWhitespace != "none" {
            drawWhitespaceGlyphs(in: rect)
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

    // MARK: - Occurrence Highlight

    func debounceOccurrenceHighlight() {
        occurrenceDebounceTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.updateOccurrenceHighlight()
        }
        occurrenceDebounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.Timing.selectionOccurrenceDebounce, execute: task)
    }

    private func updateOccurrenceHighlight() {
        occurrenceHighlightRanges = []

        let nsString = string as NSString
        guard nsString.length < Constants.Limits.maxOccurrenceHighlightDocSize else {
            needsDisplay = true
            return
        }

        guard let range = currentSymbolRange(), range.length > 1 else {
            needsDisplay = true
            return
        }

        let word = nsString.substring(with: range)
        let escaped = NSRegularExpression.escapedPattern(for: word)
        guard let regex = try? NSRegularExpression(pattern: "\\b\(escaped)\\b", options: []) else {
            needsDisplay = true
            return
        }

        let matches = regex.matches(in: string, range: NSRange(location: 0, length: nsString.length))
        occurrenceHighlightRanges = Array(
            matches.prefix(Constants.Limits.maxOccurrenceHighlightMatches)
                .map(\.range)
                .filter { $0 != range }
        )

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
