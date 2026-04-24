import AppKit
@preconcurrency import SwiftTerm

/// Subclass of SwiftTerm.TerminalView that adds NSDraggingDestination support
/// for file URLs dragged from Finder. SwiftTerm has no drag-and-drop implementation,
/// so its NSView consumes all drag events before SwiftUI can handle them.
/// This subclass registers for `.fileURL` drags only — `.string` drags are left
/// to SwiftUI's `.dropDestination(for: String.self)` handler.
final class ZionTerminalView: SwiftTerm.TerminalView {

    /// Called when the user drops one or more non-image file URLs onto the terminal.
    /// The string is already shell-escaped and ready to paste as text.
    var onFileDrop: ((String) -> Void)?
    var onDropActivated: (() -> Void)?

    /// Called to deliver raw bytes directly to the PTY.
    /// Used for Ctrl+V (0x16) image-paste signalling so TUIs like Claude Code
    /// read the NSPasteboard image natively.
    var onSendBytes: (([UInt8]) -> Void)?

    /// Called when the user Cmd-clicks a file-like token in the terminal.
    /// The path is passed as-is (may be absolute, relative, or include
    /// a `:line:col` suffix). Consumer resolves and opens.
    var onOpenPath: ((String) -> Void)?

    private var dragHighlightLayer: CALayer?

    /// File extensions we treat as images for drag-drop and paste routing.
    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "tiff", "tif", "bmp", "webp", "heic", "heif"
    ]

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard hasFileURLs(sender) else { return [] }
        showDragHighlight()
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard hasFileURLs(sender) else { return [] }
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        removeDragHighlight()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        removeDragHighlight()
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        removeDragHighlight()
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else { return false }

        let target = resolvedDropTarget(using: sender)
        target.window?.makeFirstResponder(target)
        target.onDropActivated?()

        let imageURLs = urls.filter { Self.isImageFile($0) }
        let nonImageURLs = urls.filter { !Self.isImageFile($0) }

        var handled = false

        if !imageURLs.isEmpty,
           Self.stageImageOnPasteboard(urls: imageURLs) {
            // Ctrl+V (0x16) signals Claude Code / Codex to read the NSPasteboard
            // image natively, so the TUI renders its own [Image] placeholder
            // instead of seeing a raw shell-quoted path string.
            target.onSendBytes?([0x16])
            handled = true
        }

        if !nonImageURLs.isEmpty {
            let escaped = TerminalShellEscaping.joinQuotedFileURLs(nonImageURLs)
            if !escaped.isEmpty {
                target.onFileDrop?(escaped)
                handled = true
            }
        }

        return handled
    }

    // MARK: - Image pasteboard staging

    /// True if the URL points to a file we consider an image based on extension.
    static func isImageFile(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        return imageExtensions.contains(url.pathExtension.lowercased())
    }

    /// Loads each image URL and writes it + the file URL onto NSPasteboard.general.
    /// Returns true if at least one image was staged successfully.
    @discardableResult
    static func stageImageOnPasteboard(urls: [URL]) -> Bool {
        let images: [NSImage] = urls.compactMap { NSImage(contentsOf: $0) }
        guard !images.isEmpty else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(images)
        pb.writeObjects(urls as [NSURL])
        return true
    }

    // MARK: - Helpers

    private func hasFileURLs(_ info: NSDraggingInfo) -> Bool {
        info.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
    }

    private func fileURLs(from info: NSDraggingInfo) -> [URL] {
        (info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]) ?? []
    }

    private func resolvedDropTarget(using info: NSDraggingInfo) -> ZionTerminalView {
        guard let window else { return self }
        let locationInWindow = info.draggingLocation
        if let terminal = Self.terminal(atWindowPoint: locationInWindow, in: window) {
            return terminal
        }

        if let responder = window.firstResponder as? NSView,
           let terminal = Self.closestTerminalView(from: responder) {
            return terminal
        }

        return self
    }

    static func closestTerminalView(from view: NSView?) -> ZionTerminalView? {
        var current = view
        while let node = current {
            if let terminal = node as? ZionTerminalView {
                return terminal
            }
            current = node.superview
        }
        return nil
    }

    private static func allTerminalViews(in root: NSView) -> [ZionTerminalView] {
        var terminals: [ZionTerminalView] = []

        func walk(_ node: NSView) {
            if let terminal = node as? ZionTerminalView {
                terminals.append(terminal)
            }
            node.subviews.forEach(walk)
        }

        walk(root)
        return terminals
    }

    static func terminal(atWindowPoint point: NSPoint, in window: NSWindow?) -> ZionTerminalView? {
        guard let window, let contentView = window.contentView else { return nil }
        let pointInContent = contentView.convert(point, from: nil)

        if let hitView = contentView.hitTest(pointInContent),
           let terminal = closestTerminalView(from: hitView),
           terminal.acceptsInteraction(atWindowPoint: point) {
            return terminal
        }

        return allTerminalViews(in: contentView)
            .reversed()
            .first(where: { $0.acceptsInteraction(atWindowPoint: point) })
    }

    private func acceptsInteraction(atWindowPoint point: NSPoint) -> Bool {
        guard window != nil, !isHidden, alphaValue > 0.01 else { return false }
        let pointInView = convert(point, from: nil)
        return bounds.contains(pointInView)
    }

    func applyDiscreteScroll(lines: Int) {
        guard lines != 0 else { return }
        let wheel1 = Int32(lines > 0 ? 1 : -1)

        for _ in 0..<abs(lines) {
            if let event = Self.makeDiscreteScrollEvent(wheel1: wheel1) {
                super.scrollWheel(with: event)
            } else if lines > 0 {
                scrollUp(lines: 1)
            } else {
                scrollDown(lines: 1)
            }
        }
    }

    private static func makeDiscreteScrollEvent(wheel1: Int32) -> NSEvent? {
        guard let cgEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: wheel1,
            wheel2: 0,
            wheel3: 0
        ) else {
            return nil
        }
        return NSEvent(cgEvent: cgEvent)
    }

    static func preciseScrollLineHeight(viewHeight: CGFloat, terminalRows: Int) -> CGFloat {
        let rows = max(1, terminalRows)
        let terminalRowHeight = viewHeight / CGFloat(rows)
        return max(4, terminalRowHeight * 0.75)
    }

    static func accumulatePreciseScrollStep(
        accumulator: CGFloat,
        deltaY: CGFloat,
        lineHeight: CGFloat,
        maxLinesPerEvent: Int = 6
    ) -> (lines: Int, remainder: CGFloat) {
        guard lineHeight > 0, deltaY != 0 else {
            return (0, 0)
        }

        var nextAccumulator = accumulator
        if nextAccumulator != 0, nextAccumulator.sign != deltaY.sign {
            nextAccumulator = 0
        }

        nextAccumulator += deltaY / lineHeight
        let unclampedLines = Int(nextAccumulator.rounded(.towardZero))
        guard unclampedLines != 0 else {
            return (0, nextAccumulator)
        }

        let lines = max(-maxLinesPerEvent, min(maxLinesPerEvent, unclampedLines))
        nextAccumulator -= CGFloat(lines)
        return (lines, nextAccumulator)
    }

    static func shouldHandlePreciseScroll(
        hasPreciseScrollingDeltas: Bool,
        canScroll: Bool
    ) -> Bool {
        hasPreciseScrollingDeltas && canScroll
    }

    static func shouldResetPreciseScrollAccumulator(
        phase: NSEvent.Phase,
        momentumPhase: NSEvent.Phase
    ) -> Bool {
        let endedPhases: NSEvent.Phase = [.ended, .cancelled]
        let phaseEnded = !phase.isEmpty && endedPhases.contains(phase)
        let momentumEnded = !momentumPhase.isEmpty && endedPhases.contains(momentumPhase)
        return phaseEnded || momentumEnded
    }

    // MARK: - Paste

    /// Overrides SwiftTerm's text-only paste. When the pasteboard holds an
    /// image (e.g., a screenshot), send Ctrl+V to the PTY so the TUI reads
    /// the image from NSPasteboard itself — matches native Terminal.app /
    /// iTerm2 behavior for Claude Code and Codex image paste.
    override func paste(_ sender: Any) {
        let pb = NSPasteboard.general
        if Self.pasteboardHasImage(pb), let send = onSendBytes {
            send([0x16])
            return
        }
        super.paste(sender)
    }

    static func pasteboardHasImage(_ pb: NSPasteboard) -> Bool {
        let hasImageObject = pb.canReadObject(forClasses: [NSImage.self], options: nil)
        guard hasImageObject else { return false }

        // Exclude pasteboards that only carry text — NSImage claims convertibility
        // via certain URL types, but we want the image-paste path only when
        // real image data or a recognized image file URL is present.
        if pb.canReadItem(withDataConformingToTypes: [
            NSPasteboard.PasteboardType.tiff.rawValue,
            NSPasteboard.PasteboardType.png.rawValue
        ]) {
            return true
        }
        if let urls = pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] {
            return urls.contains(where: isImageFile)
        }
        return false
    }

    // MARK: - Cmd-click file-reference open
    //
    // The actual click interception lives in
    // `TerminalTabView.Coordinator.installMouseInteractionMonitors` as an
    // `NSEvent.addLocalMonitorForEvents` handler, because SwiftTerm's
    // `mouseDown(with:)` is not `open` outside its module. The monitor
    // consults `pathToken(at:)` below and dispatches through `onOpenPath`
    // when a valid token is found.

    /// Extracts a file-like token under the mouse click, using the visible
    /// cell grid. Returns nil when the click is on whitespace or outside the
    /// buffer. Token boundaries stop on whitespace and common wrapping
    /// characters (`'"` parens, brackets, angle brackets, backticks, pipes,
    /// commas, semicolons).
    func pathToken(at event: NSEvent) -> String? {
        let terminal = getTerminal()
        let cols = terminal.cols
        let rows = terminal.rows
        guard cols > 0, rows > 0 else { return nil }

        let point = convert(event.locationInWindow, from: nil)
        let cellW = bounds.width / CGFloat(cols)
        let cellH = bounds.height / CGFloat(rows)
        guard cellW > 0, cellH > 0 else { return nil }

        let col = min(cols - 1, max(0, Int(point.x / cellW)))
        let visibleRow = min(rows - 1, max(0, Int((bounds.height - point.y) / cellH)))
        let bufferRow = visibleRow + terminal.buffer.yDisp

        var lineChars: [Character] = []
        lineChars.reserveCapacity(cols)
        for c in 0..<cols {
            let cd = terminal.buffer.getChar(atBufferRelative: Position(col: c, row: bufferRow))
            lineChars.append(cd.getCharacter())
        }

        return Self.extractPathToken(line: lineChars, at: col)
    }

    static func extractPathToken(line: [Character], at col: Int) -> String? {
        guard col >= 0, col < line.count else { return nil }

        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "'\"`()[]{}<>|,;"))
        func isSeparator(_ ch: Character) -> Bool {
            guard let scalar = ch.unicodeScalars.first else { return true }
            return separators.contains(scalar) || ch == "\0"
        }

        if isSeparator(line[col]) { return nil }

        var start = col
        while start > 0, !isSeparator(line[start - 1]) { start -= 1 }
        var end = col
        while end < line.count, !isSeparator(line[end]) { end += 1 }

        let token = String(line[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    // MARK: - Visual feedback

    private func showDragHighlight() {
        guard dragHighlightLayer == nil, let layer else { return }
        let highlight = CALayer()
        highlight.frame = layer.bounds
        highlight.borderWidth = 2
        highlight.borderColor = NSColor.controlAccentColor.cgColor
        highlight.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        highlight.cornerRadius = 4
        highlight.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer.addSublayer(highlight)
        dragHighlightLayer = highlight
    }

    private func removeDragHighlight() {
        dragHighlightLayer?.removeFromSuperlayer()
        dragHighlightLayer = nil
    }
}
