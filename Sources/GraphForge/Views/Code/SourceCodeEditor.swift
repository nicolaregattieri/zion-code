import SwiftUI
import AppKit

struct SourceCodeEditor: NSViewRepresentable {
    @Binding var text: String
    var theme: EditorTheme
    
    func makeNSView(context: Context) -> NSScrollView {
        // This factory method is the ONLY one that reliably manages the hierarchy in SwiftUI
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.drawsBackground = true
        
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
        
        let colors = getEditorColors(for: theme)
        
        // Apply theme backgrounds
        textView.backgroundColor = colors.background
        textView.insertionPointColor = colors.text
        nsView.backgroundColor = colors.background
        
        if let ruler = nsView.verticalRulerView as? LineNumberRulerView {
            ruler.theme = theme
            ruler.needsDisplay = true
        }
        
        // Highlighting
        context.coordinator.applyHighlighting(to: textView, colors: colors)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SourceCodeEditor
        init(_ parent: SourceCodeEditor) { self.parent = parent }
        
        @MainActor
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if parent.text != textView.string {
                parent.text = textView.string
            }
            applyHighlighting(to: textView, colors: parent.getEditorColors(for: parent.theme))
            textView.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }
        
        @MainActor
        func applyHighlighting(to textView: NSTextView, colors: EditorColors) {
            let string = textView.string
            let length = string.utf16.count
            guard length > 0, let textStorage = textView.textStorage else { return }
            let range = NSRange(location: 0, length: length)
            
            textStorage.beginEditing()
            
            // 1. Reset all attributes to theme base color
            textStorage.setAttributes([
                .foregroundColor: colors.text,
                .font: textView.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            ], range: range)
            
            // 2. Highlighting
            highlight(pattern: #""[^"\\\n]*(\\.[^"\\\n]*)*""#, in: string, color: colors.string, storage: textStorage)
            highlight(pattern: #"\b\d+(\.\d+)?\b"#, in: string, color: colors.number, storage: textStorage)
            
            let keywords = #"\b(func|let|var|class|struct|import|if|else|return|while|for|in|switch|case|break|continue|enum|protocol|extension|typealias|try|catch|guard|static|public|private|internal|fileprivate|open|override|final|async|await|do|self|throw|throws|as|is|where|nil|true|false)\b"#
            highlight(pattern: keywords, in: string, color: colors.keyword, storage: textStorage)
            
            highlight(pattern: #"\b[A-Z][a-zA-Z0-9_]*\b"#, in: string, color: colors.type, storage: textStorage)
            highlight(pattern: #"@[a-zA-Z0-9_]+"#, in: string, color: colors.keyword, storage: textStorage)
            highlight(pattern: #"\b[a-z][a-zA-Z0-9_]*(?=\()"#, in: string, color: colors.call, storage: textStorage)
            
            highlight(pattern: #"//.*"#, in: string, color: colors.comment, storage: textStorage)
            highlight(pattern: #"(?s)/\*.*?\*/"#, in: string, color: colors.comment, storage: textStorage)
            
            textStorage.endEditing()
        }
        
        private func highlight(pattern: String, in text: String, color: NSColor, storage: NSTextStorage) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
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
        case .everforestLight:
            return EditorColors(
                background: NSColor(srgbRed: 0.992, green: 0.980, blue: 0.933, alpha: 1.0),
                text: NSColor(srgbRed: 0.361, green: 0.416, blue: 0.373, alpha: 1.0),
                keyword: NSColor(srgbRed: 0.902, green: 0.494, blue: 0.502, alpha: 1.0),
                type: NSColor(srgbRed: 0.498, green: 0.737, blue: 0.702, alpha: 1.0),
                string: NSColor(srgbRed: 0.514, green: 0.753, blue: 0.573, alpha: 1.0),
                comment: NSColor(srgbRed: 0.576, green: 0.624, blue: 0.569, alpha: 1.0),
                number: NSColor(srgbRed: 0.839, green: 0.600, blue: 0.714, alpha: 1.0),
                call: NSColor(srgbRed: 0.859, green: 0.596, blue: 0.459, alpha: 1.0)
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
        
        let isEverforest = theme == .everforestLight
        let bg = isEverforest ? NSColor(srgbRed: 0.96, green: 0.95, blue: 0.88, alpha: 1.0) : NSColor.black.withAlphaComponent(0.15)
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
            
            let color = isEverforest ? NSColor.gray : NSColor.secondaryLabelColor
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular), .foregroundColor: color]
            let str = "\(lineNumber)" as NSString
            let size = str.size(withAttributes: attrs)
            str.draw(at: NSPoint(x: ruleThickness - size.width - 5, y: y + (lineRect.height - size.height)/2), withAttributes: attrs)
            
            index = lineRange.upperBound
            lineNumber += 1
        }
    }
}
