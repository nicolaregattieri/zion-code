import AppKit

extension ZionTextView {

    // MARK: - Key Interception

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let key = event.charactersIgnoringModifiers?.lowercased()

        if (flags == .command || flags == .control), key == "f" {
            emitFindSeedFromSelection()
            return false
        }

        if flags == .command, key == "g" {
            onFindNextShortcut?()
            return true
        }

        if flags == [.command, .shift], key == "g" {
            onFindPreviousShortcut?()
            return true
        }

        if flags == .command, key == "d" {
            selectNextOccurrence()
            return true
        }

        // Format Document (⇧⌥F)
        if flags == [.shift, .option], key == "f" {
            NotificationCenter.default.post(name: .formatDocument, object: nil)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])

        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "g" {
            onFindNextShortcut?()
            return
        }

        if flags == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "g" {
            onFindPreviousShortcut?()
            return
        }

        // VSCode-like command: add next occurrence selection.
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "d" {
            selectNextOccurrence()
            return
        }

        if isF12(event) {
            if flags == .shift {
                requestReferencesFromCaret()
                return
            }
            if flags.isEmpty {
                requestDefinitionFromCaret()
                return
            }
        }

        switch (event.keyCode, flags) {
        case (126, .option):          // Option+Up: Move line up
            moveLineUp()
            return
        case (125, .option):          // Option+Down: Move line down
            moveLineDown()
            return
        case (125, [.shift, .option]): // Shift+Option+Down: Duplicate line
            duplicateLineDown()
            return
        case (48, []) where !hasMarkedText(): // Tab: Indent
            indentLines()
            return
        case (48, .shift):            // Shift+Tab: Outdent
            outdentLines()
            return
        case (36, []), (76, []):      // Return/Enter: Auto-indent
            autoIndentNewLine()
            return
        default:
            break
        }

        // Auto-closing brackets/quotes
        if let chars = event.characters, chars.count == 1, !flags.contains(.command), !flags.contains(.control) {
            let char = chars.first!
            if handleAutoClose(char) {
                return
            }
        }

        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           let query = navigationQuery(at: event.locationInWindow) {
            onRequestDefinition?(query)
            return
        }
        super.mouseDown(with: event)
    }

    // MARK: - Delete Backward (auto-close pair removal)

    override func deleteBackward(_ sender: Any?) {
        let sel = selectedRange()
        if sel.length == 0 && sel.location > 0 && sel.location < (string as NSString).length {
            let nsString = string as NSString
            let prev = nsString.substring(with: NSRange(location: sel.location - 1, length: 1))
            let next = nsString.substring(with: NSRange(location: sel.location, length: 1))
            let pairs: [String: String] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'", "`": "`"]
            if let closing = pairs[prev], closing == next {
                let deleteRange = NSRange(location: sel.location - 1, length: 2)
                if shouldChangeText(in: deleteRange, replacementString: "") {
                    textStorage?.replaceCharacters(in: deleteRange, with: "")
                    didChangeText()
                    setSelectedRange(NSRange(location: sel.location - 1, length: 0))
                    return
                }
            }
        }
        super.deleteBackward(sender)
    }

    // MARK: - Selector-backed Shortcut Actions

    @objc
    func zionToggleComment(_ sender: Any?) {
        toggleComment()
    }

    @objc
    func zionFindNext(_ sender: Any?) {
        onFindNextShortcut?()
    }

    @objc
    func zionFindPrevious(_ sender: Any?) {
        onFindPreviousShortcut?()
    }

    @objc
    func zionSelectNextOccurrence(_ sender: Any?) {
        selectNextOccurrence()
    }

    @objc
    func zionFormatDocument(_ sender: Any?) {
        NotificationCenter.default.post(name: .formatDocument, object: nil)
    }

    func isF12(_ event: NSEvent) -> Bool {
        guard let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first else { return false }
        return Int(scalar.value) == NSF12FunctionKey
    }
}
