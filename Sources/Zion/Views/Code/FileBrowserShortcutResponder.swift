import AppKit
import SwiftUI

@MainActor
final class FileBrowserResponderReference: ObservableObject {
    weak var responder: FileBrowserShortcutResponderView?
}

struct FileBrowserShortcutResponderHost: NSViewRepresentable {
    let reference: FileBrowserResponderReference
    var canDeleteSelectedFiles: () -> Bool
    var onDeleteSelectedFiles: () -> Void
    var canRenameSelectedFile: () -> Bool
    var onRenameSelectedFile: () -> Void
    var onMoveSelection: (FileBrowserNavigationDirection, Bool) -> Void

    func makeNSView(context: Context) -> FileBrowserShortcutResponderView {
        let view = FileBrowserShortcutResponderView()
        view.reference = reference
        view.canDeleteSelectedFiles = canDeleteSelectedFiles
        view.onDeleteSelectedFiles = onDeleteSelectedFiles
        view.canRenameSelectedFile = canRenameSelectedFile
        view.onRenameSelectedFile = onRenameSelectedFile
        view.onMoveSelection = onMoveSelection
        reference.responder = view
        return view
    }

    func updateNSView(_ nsView: FileBrowserShortcutResponderView, context: Context) {
        nsView.reference = reference
        nsView.canDeleteSelectedFiles = canDeleteSelectedFiles
        nsView.onDeleteSelectedFiles = onDeleteSelectedFiles
        nsView.canRenameSelectedFile = canRenameSelectedFile
        nsView.onRenameSelectedFile = onRenameSelectedFile
        nsView.onMoveSelection = onMoveSelection
        if reference.responder !== nsView {
            reference.responder = nsView
        }
    }

}

final class FileBrowserShortcutResponderView: NSView {
    weak var reference: FileBrowserResponderReference?
    var canDeleteSelectedFiles: () -> Bool = { false }
    var onDeleteSelectedFiles: () -> Void = {}
    var canRenameSelectedFile: () -> Bool = { false }
    var onRenameSelectedFile: () -> Void = {}
    var onMoveSelection: (FileBrowserNavigationDirection, Bool) -> Void = { _, _ in }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reference?.responder = self
    }

    @objc
    func zionDeleteSelectedFiles(_ sender: Any?) {
        guard canDeleteSelectedFiles() else { return }
        onDeleteSelectedFiles()
    }

    override func insertNewline(_ sender: Any?) {
        guard canRenameSelectedFile() else {
            super.insertNewline(sender)
            return
        }
        onRenameSelectedFile()
    }

    override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
    }

    override func moveUp(_ sender: Any?) {
        onMoveSelection(.up, false)
    }

    override func moveDown(_ sender: Any?) {
        onMoveSelection(.down, false)
    }

    override func moveLeft(_ sender: Any?) {
        onMoveSelection(.left, false)
    }

    override func moveRight(_ sender: Any?) {
        onMoveSelection(.right, false)
    }

    override func moveUpAndModifySelection(_ sender: Any?) {
        onMoveSelection(.up, true)
    }

    override func moveDownAndModifySelection(_ sender: Any?) {
        onMoveSelection(.down, true)
    }

    override func moveLeftAndModifySelection(_ sender: Any?) {
        onMoveSelection(.left, true)
    }

    override func moveRightAndModifySelection(_ sender: Any?) {
        onMoveSelection(.right, true)
    }
}
