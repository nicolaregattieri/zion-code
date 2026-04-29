import AppKit

/// Clip view that forwards background clicks (below the last line of text)
/// to the document text view, placing the caret at end of document and
/// taking first responder. Mirrors VS Code behavior where clicking anywhere
/// inside the editor area focuses the cursor.
final class EditorClipView: NSClipView {
    override func mouseDown(with event: NSEvent) {
        guard let textView = documentView as? NSTextView else {
            super.mouseDown(with: event)
            return
        }

        window?.makeFirstResponder(textView)

        let length = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: length, length: 0))
        textView.scrollRangeToVisible(NSRange(location: length, length: 0))

        super.mouseDown(with: event)
    }
}
