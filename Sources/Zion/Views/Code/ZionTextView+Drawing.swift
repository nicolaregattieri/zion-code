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

    func drawRangeHighlight(range: NSRange, color: NSColor, in rect: NSRect) {
        guard let layoutManager = layoutManager, let textContainer = textContainer else { return }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var highlightRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        highlightRect.origin.y += textContainerOrigin.y
        highlightRect.origin.x += textContainerOrigin.x

        guard highlightRect.intersects(rect) else { return }

        color.setFill()
        let path = NSBezierPath(roundedRect: highlightRect.insetBy(dx: -1, dy: -1), xRadius: 2, yRadius: 2)
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
        let color = NSColor.systemBlue.withAlphaComponent(0.2)
        if let range = matchingBracketRange {
            drawRangeHighlight(range: range, color: color, in: rect)
        }
        if let range = secondBracketRange {
            drawRangeHighlight(range: range, color: color, in: rect)
        }
    }

    // MARK: - Occurrence Highlights

    func drawOccurrenceHighlights(in rect: NSRect) {
        let color = isLightTheme
            ? NSColor.systemYellow.withAlphaComponent(0.20)
            : NSColor.systemYellow.withAlphaComponent(0.15)
        for range in occurrenceHighlightRanges {
            drawRangeHighlight(range: range, color: color, in: rect)
        }
    }

    // MARK: - Render Whitespace

    func drawWhitespaceGlyphs(in rect: NSRect) {
        guard let layoutManager = layoutManager, let textContainer = textContainer, let font = self.font else { return }
        guard !string.isEmpty else { return }

        let color = isLightTheme
            ? NSColor.black.withAlphaComponent(0.18)
            : NSColor.white.withAlphaComponent(0.18)

        let dotFont = NSFont.monospacedSystemFont(ofSize: font.pointSize * 0.8, weight: .regular)
        let dotAttrs: [NSAttributedString.Key: Any] = [.font: dotFont, .foregroundColor: color]

        let middleDot: NSString = "\u{00B7}"
        let tabArrow: NSString = "\u{2192}"

        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        let nsString = string as NSString
        let mode = editorRenderWhitespace

        var lineStart = visibleCharRange.location
        while lineStart < NSMaxRange(visibleCharRange) && lineStart < nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: lineStart, length: 0))
            let lineText = nsString.substring(with: lineRange)

            // Find last non-whitespace offset for trailing mode
            var lastNonWSOffset = -1
            for (i, ch) in lineText.enumerated() {
                if ch != " " && ch != "\t" && ch != "\n" && ch != "\r" {
                    lastNonWSOffset = i
                }
            }

            for (charOffset, ch) in lineText.enumerated() {
                guard ch == " " || ch == "\t" else { continue }

                let shouldRender: Bool
                switch mode {
                case "all":
                    shouldRender = true
                case "trailing":
                    shouldRender = charOffset > lastNonWSOffset
                case "boundary":
                    let prevIsWS = charOffset == 0 || {
                        let prev = lineText[lineText.index(lineText.startIndex, offsetBy: charOffset - 1)]
                        return prev == " " || prev == "\t"
                    }()
                    let nextIsWS: Bool = {
                        let nextIdx = charOffset + 1
                        guard nextIdx < lineText.count else { return true }
                        let next = lineText[lineText.index(lineText.startIndex, offsetBy: nextIdx)]
                        return next == " " || next == "\t" || next == "\n"
                    }()
                    shouldRender = prevIsWS || nextIsWS
                default:
                    shouldRender = false
                }

                guard shouldRender else { continue }

                let charIndex = lineRange.location + charOffset
                let charRange = NSRange(location: charIndex, length: 1)
                let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
                var glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                glyphRect.origin.y += textContainerOrigin.y
                glyphRect.origin.x += textContainerOrigin.x

                guard glyphRect.intersects(rect) else { continue }

                let glyph: NSString = ch == "\t" ? tabArrow : middleDot
                let glyphSize = glyph.size(withAttributes: dotAttrs)
                let drawPoint = NSPoint(
                    x: glyphRect.origin.x + (glyphRect.width - glyphSize.width) / 2,
                    y: glyphRect.origin.y + (glyphRect.height - glyphSize.height) / 2
                )
                glyph.draw(at: drawPoint, withAttributes: dotAttrs)
            }

            lineStart = NSMaxRange(lineRange)
        }
    }
}

// MARK: - Line Number Ruler

class LineNumberRulerView: NSRulerView {
    var theme: EditorTheme = .dracula
    /// 1-based line numbers (new side) -> change kind. Painted as a 3pt
    /// colored bar on the right edge of the gutter. Empty map = no bars.
    var diffMarkers: [Int: EditorLineChangeKind] = [:]
    /// Pre-change content for modified/deleted lines. Hovering the colored
    /// bar shows a popover with these lines so the user can compare new vs.
    /// old without opening the Changes tab.
    var diffOriginalByLine: [Int: [String]] = [:]
    /// Tracked by `SourceCodeEditor` to detect when the parent VM published
    /// new markers and the ruler should refresh.
    var diffMarkersVersion: Int = 0
    /// Rebuilt every time `drawHashMarksAndLabels` runs. Maps the bar rect to
    /// the line number it represents; consumed by `mouseMoved` to drive the
    /// diff popover.
    private var hitRegions: [(rect: NSRect, line: Int)] = []
    private var trackingArea: NSTrackingArea?
    private var diffPopover: NSPopover?
    private var hoveredLine: Int?

    init(textView: NSTextView) {
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 35
    }
    required init(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        var found: Int?
        for region in hitRegions where region.rect.contains(point) {
            found = region.line
            break
        }
        if found != hoveredLine {
            hoveredLine = found
            if let line = found, let original = diffOriginalByLine[line], !original.isEmpty {
                showDiffPopover(forLine: line, lines: original, at: point)
            } else {
                diffPopover?.close()
                diffPopover = nil
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredLine = nil
        // Defer close so the user can move the cursor from the bar into the
        // popover to copy text. `behavior = .transient` still dismisses on
        // any outside click, so this only postpones leak-on-leave.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.hoveredLine == nil else { return }
            self.diffPopover?.close()
            self.diffPopover = nil
        }
    }

    private func showDiffPopover(forLine line: Int, lines: [String], at point: NSPoint) {
        diffPopover?.close()
        let content = NSViewController()
        let width: CGFloat = 480
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 0))
        textView.isEditable = false
        textView.isSelectable = true
        // Let NSPopover render its native vibrancy backdrop so the popover
        // matches macOS HIG. Filling our own bg would clash with the system
        // chrome under reduced-transparency / accessibility modes.
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 10, height: 8)
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let body = NSMutableAttributedString()
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        body.append(NSAttributedString(string: L10n("editor.diff.popover.previous") + "\n", attributes: headerAttrs))
        let lineAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(DesignSystem.Colors.diffDeletion)
        ]
        let bodyText = lines.map { "- " + $0 }.joined(separator: "\n")
        body.append(NSAttributedString(string: bodyText, attributes: lineAttrs))
        textView.textStorage?.setAttributedString(body)
        let lineHeight = font.pointSize + 5
        let height = max(48, CGFloat(lines.count + 1) * lineHeight + 24)
        textView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let host = NSView(frame: textView.frame)
        host.addSubview(textView)
        content.view = host
        let popover = NSPopover()
        popover.contentViewController = content
        popover.behavior = .transient
        popover.animates = false
        let anchor = NSRect(x: ruleThickness - 4, y: point.y - 2, width: 4, height: 4)
        popover.show(relativeTo: anchor, of: self, preferredEdge: .maxX)
        diffPopover = popover
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = clientView as? NSTextView, let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }
        hitRegions.removeAll(keepingCapacity: true)

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

            // VS Code-style change bar on the right edge of the gutter.
            // `.deleted` is drawn as a downward chevron above the line so
            // the user can locate vanished content without expanding hunks.
            if let kind = diffMarkers[lineNumber] {
                let barColor: NSColor
                switch kind {
                case .added:
                    barColor = NSColor(DesignSystem.Colors.diffAddition)
                case .modified:
                    // VS Code uses info-blue for modified diff bars. Reusing
                    // `Colors.info` keeps theme drift centralized and avoids
                    // hardcoded sRGB literals.
                    barColor = NSColor(DesignSystem.Colors.info)
                case .deleted:
                    barColor = NSColor(DesignSystem.Colors.diffDeletion)
                }
                barColor.set()
                if kind == .deleted {
                    // Downward triangle pointing at the gap above the line.
                    let cx = ruleThickness - 3
                    let cy = y + 2
                    let path = NSBezierPath()
                    path.move(to: NSPoint(x: cx - 4, y: cy))
                    path.line(to: NSPoint(x: cx + 4, y: cy))
                    path.line(to: NSPoint(x: cx, y: cy + 5))
                    path.close()
                    path.fill()
                    let hit = NSRect(x: cx - 5, y: cy - 2, width: 12, height: 10)
                    hitRegions.append((hit, lineNumber))
                } else {
                    let bar = NSRect(x: ruleThickness - 3, y: y, width: 3, height: lineRect.height)
                    bar.fill()
                    // Pad the hit area horizontally so hovering near the bar
                    // still triggers the popover — a 3pt-wide target is too
                    // narrow to grab reliably with a trackpad.
                    let hit = NSRect(x: ruleThickness - 10, y: y, width: 12, height: lineRect.height)
                    hitRegions.append((hit, lineNumber))
                }
            }

            index = lineRange.upperBound
            lineNumber += 1
        }
    }
}
