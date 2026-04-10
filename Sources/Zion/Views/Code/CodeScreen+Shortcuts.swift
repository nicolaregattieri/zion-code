import AppKit
import SwiftUI

extension CodeScreen {

    // MARK: - Keyboard Shortcut Routing

    /// Routes Cmd+F / Ctrl+F to the correct pane based on current focus.
    func routeFindShortcut() {
        if isImagePreviewActive {
            return
        }
        if layout == .terminalOnly {
            toggleTerminalSearch()
        } else if layout == .editorOnly {
            toggleSearch()
        } else {
            // Split: if terminal search is already visible, keep toggling it
            // (the search TextField has focus, not TerminalView itself)
            if isTerminalSearchVisible || isTerminalFocused() {
                toggleTerminalSearch()
            } else {
                toggleSearch()
            }
        }
    }

    func handleEscapeShortcut() {
        if isMarkdownFullscreen {
            withAnimation(DesignSystem.Motion.detail) {
                isMarkdownFullscreen = false
            }
            return
        }
        if sidebarMode == .findInFiles && isFileBrowserVisible {
            closeFindInFilesPanel()
            return
        }
        if isTerminalSearchVisible {
            closeTerminalSearch()
            return
        }
        if isSearchVisible {
            closeSearch()
        }
    }

    /// Walks the responder chain to detect if a SwiftTerm TerminalView has focus.
    func isTerminalFocused() -> Bool {
        guard let window = NSApp.keyWindow,
              let resp = window.firstResponder as? NSView else { return false }
        var current: NSView? = resp
        while let v = current {
            if String(describing: type(of: v)).contains("TerminalView") { return true }
            current = v.superview
        }
        return false
    }
}
