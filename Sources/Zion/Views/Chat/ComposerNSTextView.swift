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
    /// Optional hook the composer wires up to capture image / PDF / file
    /// URL paste events. When set, the NSTextView intercepts paste before
    /// the system inserts a path-as-text, hands the pasteboard to the
    /// composer, and only falls back to the default paste if no
    /// attachment was captured.
    var onPasteAttachments: (([PendingChatAttachment]) -> Void)? = nil

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

        // MARK: Slash autocomplete

        /// Called from ZionComposerTextView after '/' has been inserted at line start.
        @MainActor func maybeShowSlashAutocomplete() {
            guard let tv = textView, let window = tv.window else { return }

            // Refresh the skill index in the background so newly added / edited
            // skills appear without restarting the app. The first render uses
            // whatever is already cached; if reload() picks up new items, the
            // next keystroke (which triggers updateSlashFilter) will reflect them.
            Self.refreshSkillIndexIfNeeded()

            let registry = SlashCommandRegistry.shared
            let items = registry.match(prefix: "/")
            guard !items.isEmpty else { return }

            let caretRect = tv.firstRect(forCharacterRange: tv.selectedRange(), actualRange: nil)
            SlashAutocompletePanel.shared.show(anchor: caretRect, in: window, items: items) { [weak self] picked in
                self?.commitSlash(picked)
            }
        }

        // MARK: Skill index refresh (throttled)

        /// Timestamp of the last `SkillIndex.shared.reload()` we triggered.
        /// Used to avoid spamming disk scans on every '/' keystroke.
        @MainActor private static var lastSkillReload: Date = .distantPast
        private static let skillReloadMinInterval: TimeInterval = 2.0

        /// Fire-and-forget reload of the shared skill index, throttled to once
        /// every `skillReloadMinInterval` seconds.
        @MainActor
        private static func refreshSkillIndexIfNeeded() {
            let now = Date()
            guard now.timeIntervalSince(lastSkillReload) >= skillReloadMinInterval else { return }
            lastSkillReload = now
            Task { @MainActor in
                await SlashCommandRegistry.shared.reloadSkills()
            }
        }

        /// Update slash filter as user continues typing after '/'.
        @MainActor func updateSlashFilter() {
            guard let tv = textView else { return }
            guard SlashAutocompletePanel.shared.isShown else { return }

            let nsString = tv.string as NSString
            let insertionPoint = tv.selectedRange().location

            // Walk back to find '/'
            var pos = insertionPoint - 1
            while pos >= 0 {
                let ch = nsString.character(at: pos)
                let scalar = Unicode.Scalar(ch)!
                if ch == UInt16(("/".unicodeScalars.first!).value) {
                    break
                }
                if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                    SlashAutocompletePanel.shared.dismiss()
                    return
                }
                pos -= 1
            }
            guard pos >= 0 else {
                SlashAutocompletePanel.shared.dismiss()
                return
            }

            let prefix = nsString.substring(with: NSRange(location: pos, length: insertionPoint - pos))
            let registry = SlashCommandRegistry.shared
            let items = registry.match(prefix: prefix)
            if items.isEmpty {
                SlashAutocompletePanel.shared.dismiss()
            } else {
                guard let tv = textView, let window = tv.window else { return }
                let caretRect = tv.firstRect(forCharacterRange: tv.selectedRange(), actualRange: nil)
                SlashAutocompletePanel.shared.show(anchor: caretRect, in: window, items: items) { [weak self] picked in
                    self?.commitSlash(picked)
                }
            }
        }

        /// Replace the /token with `picked.name + " "`.
        func commitSlash(_ picked: SlashItem) {
            guard let tv = textView else { return }
            let nsString = tv.string as NSString
            let insertionPoint = tv.selectedRange().location

            // Walk back from insertion point to find '/'
            var slashPos = insertionPoint - 1
            while slashPos >= 0 {
                let ch = nsString.character(at: slashPos)
                if ch == UInt16(("/".unicodeScalars.first!).value) { break }
                slashPos -= 1
            }
            guard slashPos >= 0 else { return }

            let replaceRange = NSRange(location: slashPos, length: insertionPoint - slashPos)
            let replacement = picked.name + " "
            // TODO(P14.5): inline ghost-text arg hint
            if tv.shouldChangeText(in: replaceRange, replacementString: replacement) {
                tv.textStorage?.replaceCharacters(in: replaceRange, with: replacement)
                tv.didChangeText()
                tv.setSelectedRange(NSRange(location: slashPos + replacement.count, length: 0))
            }
            parent.text = tv.string
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

    /// Tell NSTextView's paste validator that we accept images, PDFs, and
    /// file URLs in addition to plain text / RTF. Without this NSTextView
    /// short-circuits Cmd+V (system beep, no `paste(_:)` call) whenever the
    /// pasteboard only carries an image — because the default
    /// `readablePasteboardTypes` excludes images.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        return super.readablePasteboardTypes + [
            .png, .tiff, .fileURL,
            NSPasteboard.PasteboardType("public.image"),
            NSPasteboard.PasteboardType("com.adobe.pdf"),
            NSPasteboard.PasteboardType("public.file-url")
        ]
    }

    /// Some macOS validators short-circuit on `validateMenuItem` for paste
    /// when the readable types don't match. Force-enable the menu item so
    /// our `paste(_:)` override runs and decides what to do with the
    /// pasteboard.
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(NSText.paste(_:)) {
            return true
        }
        return super.validateMenuItem(menuItem)
    }

    /// Intercepts Cmd+V. When the pasteboard carries an image (raw image
    /// data or a file URL to an image / PDF), we capture it as an
    /// attachment via the composer callback instead of letting the system
    /// paste the file path or TIFF blob as plain text. When nothing
    /// captureable is found, we fall back to NSTextView's default paste.
    override func paste(_ sender: Any?) {
        if let coordinator = delegate as? ComposerNSTextView.Coordinator,
           let handler = coordinator.parent.onPasteAttachments {
            let captured = ChatAttachmentService.captureFromPasteboard()
            if !captured.isEmpty {
                handler(captured)
                return
            }
        }
        super.paste(sender)
    }

    override func keyDown(with event: NSEvent) {
        let coordinator = delegate as? ComposerNSTextView.Coordinator

        // Forward keys to slash panel if visible
        if SlashAutocompletePanel.shared.isShown {
            switch event.keyCode {
            case 125: // Arrow down
                if SlashAutocompletePanel.shared.handleKey(.down) { return }
            case 126: // Arrow up
                if SlashAutocompletePanel.shared.handleKey(.up) { return }
            case 36:  // Return (no shift → commit; with shift → pass through)
                if !event.modifierFlags.contains(.shift) {
                    if SlashAutocompletePanel.shared.handleKey(.returnKey) { return }
                }
            case 48:  // Tab → commit
                if SlashAutocompletePanel.shared.handleKey(.tab) { return }
            case 53:  // Escape → dismiss
                if SlashAutocompletePanel.shared.handleKey(.escape) { return }
            default:
                break
            }
        }

        // Enter (no shift) → send (mention panel check)
        if event.keyCode == 36 && !event.modifierFlags.contains(.shift) {
            if coordinator?.commitSelectedInPanel() == true {
                // Panel consumed it
                return
            }
            coordinator?.handleSend()
            return
        }

        // Escape → dismiss mention panel
        if event.keyCode == 53 {
            if let coord = coordinator, coord.autocompletePanel != nil {
                coord.dismissAutocomplete()
                return
            }
        }

        // Arrow up (mention panel)
        if event.keyCode == 126 {
            if coordinator?.forwardArrowKey(.up) == true { return }
        }

        // Arrow down (mention panel)
        if event.keyCode == 125 {
            if coordinator?.forwardArrowKey(.down) == true { return }
        }

        // Tab → commit from mention panel
        if event.keyCode == 48 {
            if coordinator?.commitSelectedInPanel() == true { return }
        }

        // '@' trigger — insert first, then check boundary
        if let chars = event.charactersIgnoringModifiers, chars == "@" {
            super.keyDown(with: event)
            coordinator?.maybeShowAutocomplete()
            return
        }

        // '/' trigger — show slash autocomplete at line start OR after whitespace.
        // Mirrors '@' behavior so users can drop slash commands mid-message
        // (e.g. "look at /diff" suggests /diff completion).
        if let chars = event.charactersIgnoringModifiers, chars == "/" {
            let insertion = selectedRange().location
            let nsString = (self.string as NSString)
            let prevCharOK: Bool
            if insertion == 0 {
                prevCharOK = true
            } else {
                let prev = nsString.character(at: insertion - 1)
                let scalar = Unicode.Scalar(prev)!
                prevCharOK = CharacterSet.whitespacesAndNewlines.contains(scalar)
            }
            if prevCharOK {
                super.keyDown(with: event) // insert the slash
                coordinator?.maybeShowSlashAutocomplete()
                return
            }
        }

        super.keyDown(with: event)

        // After any other key, update prefix if mention panel is open
        coordinator?.updateAutocompletePrefix()

        // After any other key, update slash filter if slash panel is open
        if SlashAutocompletePanel.shared.isShown {
            coordinator?.updateSlashFilter()
        }
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
