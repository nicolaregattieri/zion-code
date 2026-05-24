// ComposerNSTextView.swift
// NSViewRepresentable wrapping NSTextView for the chat composer.
// Supports multi-line, shift-enter newline, enter-to-send, font scaling from P10,
// and @ trigger detection for MentionAutocompletePanel.
//
// Phase 12, Task 8.

import AppKit
import SwiftUI

// MARK: - ComposerNSTextView

struct ComposerNSTextView: NSViewRepresentable {

    @Binding var text: String
    var onSend: () -> Void

    @Environment(\.chatFontSizePx) private var fontSizePx
    @Environment(\.chatLineSpacingPx) private var lineSpacingPx

    // MARK: NSViewRepresentable

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ZionComposerTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]

        // Disable smart substitutions that mess with code
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.autoresizingMask = [.width]

        context.coordinator.textView = textView
        applyTypingAttributes(to: textView, fontSizePx: fontSizePx, lineSpacingPx: lineSpacingPx)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ZionComposerTextView else { return }
        context.coordinator.parent = self

        // Sync font/spacing changes
        applyTypingAttributes(to: textView, fontSizePx: fontSizePx, lineSpacingPx: lineSpacingPx)

        // Sync text only if it changed externally (e.g. clear after send)
        let currentText = textView.string
        if currentText != text {
            textView.string = text
            // Re-apply paragraph style after setting string
            applyTypingAttributes(to: textView, fontSizePx: fontSizePx, lineSpacingPx: lineSpacingPx)
        }

        // Focus management
        if text.isEmpty, let window = textView.window {
            window.makeFirstResponder(textView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: - Private helpers

    private func applyTypingAttributes(to textView: NSTextView, fontSizePx: Int, lineSpacingPx: Int) {
        let font = NSFont.systemFont(ofSize: CGFloat(fontSizePx))

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = CGFloat(lineSpacingPx)
        paragraphStyle.lineBreakMode = .byWordWrapping

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.labelColor
        ]
        textView.typingAttributes = attrs

        // Apply to existing text if present
        if !textView.string.isEmpty {
            let range = NSRange(location: 0, length: (textView.string as NSString).length)
            textView.textStorage?.setAttributes(attrs, range: range)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {

        var parent: ComposerNSTextView
        weak var textView: ZionComposerTextView?
        var autocompletePanel: MentionAutocompletePanel?

        init(parent: ComposerNSTextView) {
            self.parent = parent
        }

        // MARK: NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let newText = tv.string
            if parent.text != newText {
                parent.text = newText
            }
        }

        // MARK: Send

        func handleSend() {
            dismissAutocomplete()
            parent.onSend()
        }

        // MARK: Autocomplete

        /// Called by ZionComposerTextView after '@' has been inserted.
        func maybeShowAutocomplete() {
            guard let tv = textView else { return }
            let nsString = tv.string as NSString
            let insertionPoint = tv.selectedRange().location
            // '@' was just inserted before insertion point
            let atPos = insertionPoint - 1
            guard atPos >= 0 else { return }
            guard nsString.substring(with: NSRange(location: atPos, length: 1)) == "@" else { return }

            // Previous char must be whitespace, newline, or start-of-string
            let prevOK: Bool
            if atPos == 0 {
                prevOK = true
            } else {
                let prevChar = nsString.character(at: atPos - 1)
                let scalar = Unicode.Scalar(prevChar)!
                prevOK = CharacterSet.whitespacesAndNewlines.contains(scalar)
            }
            guard prevOK else { return }

            // Don't trigger inside a code fence
            guard !isInsideCodeFence(nsString, at: atPos) else { return }

            // Determine caret rect in screen coordinates
            let charRect = tv.firstRect(forCharacterRange: NSRange(location: atPos, length: 1), actualRange: nil)
            presentAutocomplete(anchorRect: charRect, prefix: "")
        }

        /// Update prefix as user continues typing after '@'
        func updateAutocompletePrefix() {
            guard let tv = textView, let panel = autocompletePanel else { return }
            let nsString = tv.string as NSString
            let insertionPoint = tv.selectedRange().location
            // Walk back to find '@'
            var pos = insertionPoint - 1
            while pos >= 0 {
                let ch = nsString.character(at: pos)
                let scalar = Unicode.Scalar(ch)!
                if ch == UInt16(("@" as Unicode.Scalar).value) {
                    break
                }
                if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                    // Lost the @ — dismiss
                    dismissAutocomplete()
                    return
                }
                pos -= 1
            }
            guard pos >= 0 else {
                dismissAutocomplete()
                return
            }
            let atPos = pos
            let prefix = nsString.substring(with: NSRange(location: atPos + 1, length: insertionPoint - atPos - 1))
            panel.updatePrefix(prefix)
        }

        func presentAutocomplete(anchorRect: NSRect, prefix: String) {
            guard let tv = textView, let window = tv.window else { return }
            dismissAutocomplete()

            let panel = MentionAutocompletePanel.make(anchorRect: anchorRect, in: window, prefix: prefix)
            panel.onCommit = { [weak self] suggestion in
                self?.commitMention(suggestion)
            }
            panel.onDismiss = { [weak self] in
                self?.dismissAutocomplete()
            }
            panel.orderFront(nil)
            autocompletePanel = panel
        }

        func dismissAutocomplete() {
            autocompletePanel?.orderOut(nil)
            autocompletePanel = nil
        }

        func commitMention(_ suggestion: String) {
            guard let tv = textView else { return }
            dismissAutocomplete()

            let nsString = tv.string as NSString
            let insertionPoint = tv.selectedRange().location
            // Walk back from insertion point to find '@'
            var atPos = insertionPoint - 1
            while atPos >= 0 {
                let ch = nsString.character(at: atPos)
                if ch == UInt16(("@" as Unicode.Scalar).value) { break }
                atPos -= 1
            }
            guard atPos >= 0 else { return }

            // Replace from '@' to current insertion point with the selected suggestion
            let replaceRange = NSRange(location: atPos, length: insertionPoint - atPos)
            let replacement = "@file \(suggestion) "
            if tv.shouldChangeText(in: replaceRange, replacementString: replacement) {
                tv.textStorage?.replaceCharacters(in: replaceRange, with: replacement)
                tv.didChangeText()
                tv.setSelectedRange(NSRange(location: atPos + replacement.count, length: 0))
            }
            parent.text = tv.string
        }

        // MARK: Arrow key forwarding (called from ZionComposerTextView)

        func forwardArrowKey(_ key: ArrowKey) -> Bool {
            guard let panel = autocompletePanel else { return false }
            panel.handleArrow(key)
            return true
        }

        func commitSelectedInPanel() -> Bool {
            guard let panel = autocompletePanel else { return false }
            panel.commitSelected()
            return true
        }

        // MARK: Code fence detection

        private func isInsideCodeFence(_ string: NSString, at position: Int) -> Bool {
            let text = string.substring(to: position)
            var count = 0
            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(of: "```", range: searchRange) {
                count += 1
                searchRange = range.upperBound..<text.endIndex
            }
            return count % 2 == 1
        }
    }
}

// MARK: - ZionComposerTextView

enum ArrowKey { case up, down }

final class ZionComposerTextView: NSTextView {

    override func keyDown(with event: NSEvent) {
        let coordinator = delegate as? ComposerNSTextView.Coordinator

        // Enter (no shift) → send
        if event.keyCode == 36 && !event.modifierFlags.contains(.shift) {
            if coordinator?.commitSelectedInPanel() == true {
                // Panel consumed it
                return
            }
            coordinator?.handleSend()
            return
        }

        // Escape → dismiss panel
        if event.keyCode == 53 {
            if let coord = coordinator, coord.autocompletePanel != nil {
                coord.dismissAutocomplete()
                return
            }
        }

        // Arrow up
        if event.keyCode == 126 {
            if coordinator?.forwardArrowKey(.up) == true { return }
        }

        // Arrow down
        if event.keyCode == 125 {
            if coordinator?.forwardArrowKey(.down) == true { return }
        }

        // Tab → commit from panel
        if event.keyCode == 48 {
            if coordinator?.commitSelectedInPanel() == true { return }
        }

        // '@' trigger — insert first, then check boundary
        if let chars = event.charactersIgnoringModifiers, chars == "@" {
            super.keyDown(with: event)
            coordinator?.maybeShowAutocomplete()
            return
        }

        super.keyDown(with: event)

        // After any other key, update prefix if panel is open
        coordinator?.updateAutocompletePrefix()
    }

    // MARK: Intrinsic size (grows with content, capped at ~6 lines via outer view)

    override var intrinsicContentSize: NSSize {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else {
            return super.intrinsicContentSize
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return NSSize(width: NSView.noIntrinsicMetric, height: usedRect.height + textContainerInset.height * 2)
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }
}
