import AppKit
@preconcurrency import SwiftTerm

/// Subclass of SwiftTerm.TerminalView that adds NSDraggingDestination support
/// for file URLs dragged from Finder. SwiftTerm has no drag-and-drop implementation,
/// so its NSView consumes all drag events before SwiftUI can handle them.
/// This subclass handles file URL and string drags at the pane level so split
/// layouts can route drops to the exact terminal under the cursor.
final class ZionTerminalView: SwiftTerm.TerminalView {

    /// Called when the user drops one or more file URLs onto the terminal.
    /// The string is already shell-escaped and ready to paste.
    var onFileDrop: ((String) -> Void)?
    var onDropActivated: (() -> Void)?

    private var dragHighlightLayer: CALayer?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .string])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard hasSupportedPayload(sender) else { return [] }
        showDragHighlight()
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard hasSupportedPayload(sender) else { return [] }
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
        guard let droppedText = droppedText(from: sender), !droppedText.isEmpty else { return false }

        let target = resolvedDropTarget(using: sender)
        target.window?.makeFirstResponder(target)
        target.onDropActivated?()
        target.onFileDrop?(droppedText)
        return true
    }

    // MARK: - Helpers

    private func hasSupportedPayload(_ info: NSDraggingInfo) -> Bool {
        hasFileURLs(info) || hasStringPayload(info)
    }

    private func hasFileURLs(_ info: NSDraggingInfo) -> Bool {
        info.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
    }

    private func hasStringPayload(_ info: NSDraggingInfo) -> Bool {
        info.draggingPasteboard.canReadObject(
            forClasses: [NSString.self],
            options: nil
        )
    }

    private func fileURLs(from info: NSDraggingInfo) -> [URL] {
        let raw = (info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]) ?? []

        var seen = Set<String>()
        var unique: [URL] = []
        for url in raw {
            let key = url.standardizedFileURL.path
            if seen.insert(key).inserted {
                unique.append(url)
            }
        }
        return unique
    }

    private func droppedText(from info: NSDraggingInfo) -> String? {
        let urls = fileURLs(from: info)
        if !urls.isEmpty {
            let escaped = TerminalShellEscaping.joinQuotedFileURLs(urls)
            return escaped.isEmpty ? nil : escaped
        }

        let strings = (info.draggingPasteboard.readObjects(
            forClasses: [NSString.self],
            options: nil
        ) as? [NSString]) ?? []
        guard let first = strings.first?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !first.isEmpty else { return nil }
        return String(first)
    }

    private func resolvedDropTarget(using info: NSDraggingInfo) -> ZionTerminalView {
        guard let window, let contentView = window.contentView else { return self }
        let locationInWindow = info.draggingLocation
        let locationInContent = contentView.convert(locationInWindow, from: nil)

        if let hitView = contentView.hitTest(locationInContent),
           let terminal = Self.closestTerminalView(from: hitView),
           terminal.acceptsDrop(atWindowPoint: locationInWindow) {
            return terminal
        }

        if let terminal = Self.allTerminalViews(in: contentView)
            .reversed()
            .first(where: { $0.acceptsDrop(atWindowPoint: locationInWindow) }) {
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

    private func acceptsDrop(atWindowPoint point: NSPoint) -> Bool {
        guard window != nil, !isHidden, alphaValue > 0.01 else { return false }
        let pointInView = convert(point, from: nil)
        return bounds.contains(pointInView)
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
