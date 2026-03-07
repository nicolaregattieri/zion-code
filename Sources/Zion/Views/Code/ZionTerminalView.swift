import AppKit
@preconcurrency import SwiftTerm

/// Subclass of SwiftTerm.TerminalView that adds NSDraggingDestination support
/// for file URLs dragged from Finder. SwiftTerm has no drag-and-drop implementation,
/// so its NSView consumes all drag events before SwiftUI can handle them.
/// This subclass registers for `.fileURL` drags only — `.string` drags are left
/// to SwiftUI's `.dropDestination(for: String.self)` handler.
final class ZionTerminalView: SwiftTerm.TerminalView {

    /// Called when the user drops one or more file URLs onto the terminal.
    /// The string is already shell-escaped and ready to paste.
    var onFileDrop: ((String) -> Void)?
    var onDropActivated: (() -> Void)?

    private var dragHighlightLayer: CALayer?

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
        let escaped = TerminalShellEscaping.joinQuotedFileURLs(urls)
        guard !escaped.isEmpty else { return false }

        let target = resolvedDropTarget(using: sender)
        target.onDropActivated?()
        target.onFileDrop?(escaped)
        return true
    }

    override func linefeed(source: Terminal) {
        // Keep drag selection stable even while long-running CLIs stream output.
        // SwiftTerm's default linefeed clears selection in mouse-reporting mode.
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
        guard let contentView = window?.contentView else { return self }
        let locationInContent = contentView.convert(info.draggingLocation, from: nil)
        let hitView = contentView.hitTest(locationInContent)
        return Self.closestTerminalView(from: hitView) ?? self
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
