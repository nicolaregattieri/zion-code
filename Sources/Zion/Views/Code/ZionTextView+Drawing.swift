import AppKit

extension ZionTextView {

    // MARK: - Column Ruler

    func drawColumnRuler(in rect: NSRect) {
        guard let font = self.font else { return }
        let charWidth = NSString("m").size(withAttributes: [.font: font]).width
        let x = textContainerOrigin.x + charWidth * CGFloat(columnRulerPosition)
        guard rect.minX <= x && x <= rect.maxX else { return }

        let color = isLightTheme
            ? NSColor.black.withAlphaComponent(0.15)
            : NSColor.white.withAlphaComponent(0.15)
        color.setStroke()

        let path = NSBezierPath()
        path.move(to: NSPoint(x: x, y: rect.minY))
        path.line(to: NSPoint(x: x, y: rect.maxY))
        path.lineWidth = 1.0
        path.stroke()
    }

    func drawBracketHighlight(range: NSRange, in rect: NSRect) {
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

    func drawIndentGuides(in rect: NSRect) {
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

    func drawBracketHighlightPair(in rect: NSRect) {
        if let range = matchingBracketRange {
            drawBracketHighlight(range: range, in: rect)
        }
        if let range = secondBracketRange {
            drawBracketHighlight(range: range, in: rect)
        }
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
