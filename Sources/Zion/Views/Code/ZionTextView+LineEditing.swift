import AppKit

extension ZionTextView {

    // MARK: - Move Line Up

    func moveLineUp() {
        let nsString = string as NSString
        let cursorPos = selectedRange().location
        let currentLineRange = nsString.lineRange(for: NSRange(location: cursorPos, length: 0))
        guard currentLineRange.location > 0 else { return }

        let prevLineRange = nsString.lineRange(for: NSRange(location: currentLineRange.location - 1, length: 0))
        var currentLine = nsString.substring(with: currentLineRange)
        var prevLine = nsString.substring(with: prevLineRange)

        // Handle last line (no trailing newline)
        if !currentLine.hasSuffix("\n") {
            currentLine += "\n"
            prevLine = String(prevLine.dropLast())
        }

        let combinedRange = NSRange(location: prevLineRange.location, length: prevLineRange.length + currentLineRange.length)
        let replacement = currentLine + prevLine
        let offsetInLine = cursorPos - currentLineRange.location
        let maxOffset = max(0, (currentLine as NSString).length - 1)
        let newCursorPos = prevLineRange.location + min(offsetInLine, maxOffset)

        if shouldChangeText(in: combinedRange, replacementString: replacement) {
            textStorage?.replaceCharacters(in: combinedRange, with: replacement)
            didChangeText()
            setSelectedRange(NSRange(location: newCursorPos, length: 0))
        }
    }

    // MARK: - Move Line Down

    func moveLineDown() {
        let nsString = string as NSString
        let cursorPos = selectedRange().location
        let currentLineRange = nsString.lineRange(for: NSRange(location: cursorPos, length: 0))
        let endOfCurrent = NSMaxRange(currentLineRange)
        guard endOfCurrent < nsString.length else { return }

        let nextLineRange = nsString.lineRange(for: NSRange(location: endOfCurrent, length: 0))
        var currentLine = nsString.substring(with: currentLineRange)
        var nextLine = nsString.substring(with: nextLineRange)

        // Handle last line (no trailing newline on the next line)
        if !nextLine.hasSuffix("\n") {
            nextLine += "\n"
            currentLine = String(currentLine.dropLast())
        }

        let combinedRange = NSRange(location: currentLineRange.location, length: currentLineRange.length + nextLineRange.length)
        let replacement = nextLine + currentLine
        let offsetInLine = cursorPos - currentLineRange.location
        let newCursorPos = currentLineRange.location + (nextLine as NSString).length + min(offsetInLine, (currentLine as NSString).length)

        if shouldChangeText(in: combinedRange, replacementString: replacement) {
            textStorage?.replaceCharacters(in: combinedRange, with: replacement)
            didChangeText()
            setSelectedRange(NSRange(location: newCursorPos, length: 0))
        }
    }

    // MARK: - Duplicate Line Down

    func duplicateLineDown() {
        let nsString = string as NSString
        let sel = selectedRange()
        let linesRange = nsString.lineRange(for: sel)
        let block = nsString.substring(with: linesRange)
        let insertPos = NSMaxRange(linesRange)

        var insertion: String
        var shift: Int
        if block.hasSuffix("\n") {
            insertion = block
            shift = (insertion as NSString).length
        } else {
            // Last line — prepend newline
            insertion = "\n" + block
            shift = (insertion as NSString).length
        }

        if shouldChangeText(in: NSRange(location: insertPos, length: 0), replacementString: insertion) {
            textStorage?.replaceCharacters(in: NSRange(location: insertPos, length: 0), with: insertion)
            didChangeText()
            setSelectedRange(NSRange(location: sel.location + shift, length: sel.length))
        }
    }

    // MARK: - Indent / Outdent

    func indentLines() {
        let nsString = string as NSString
        let sel = selectedRange()
        let indent = indentString

        if sel.length == 0 {
            if editorUseTabs {
                insertText("\t", replacementRange: sel)
            } else {
                let nsString = string as NSString
                let lineRange = nsString.lineRange(for: NSRange(location: sel.location, length: 0))
                let textBeforeCursor = nsString.substring(
                    with: NSRange(location: lineRange.location, length: sel.location - lineRange.location)
                )
                var column = 0
                for ch in textBeforeCursor {
                    if ch == "\t" {
                        column = ((column / editorTabSize) + 1) * editorTabSize
                    } else {
                        column += 1
                    }
                }
                let spacesNeeded = editorTabSize - (column % editorTabSize)
                insertText(String(repeating: " ", count: spacesNeeded), replacementRange: sel)
            }
            return
        }

        let lineRange = nsString.lineRange(for: sel)
        let text = nsString.substring(with: lineRange)
        let lines = text.components(separatedBy: "\n")
        let indented = lines.enumerated().map { index, line in
            if index == lines.count - 1 && line.isEmpty { return line }
            return indent + line
        }.joined(separator: "\n")

        if shouldChangeText(in: lineRange, replacementString: indented) {
            textStorage?.replaceCharacters(in: lineRange, with: indented)
            didChangeText()
            setSelectedRange(NSRange(location: lineRange.location, length: (indented as NSString).length))
        }
    }

    func outdentLines() {
        let nsString = string as NSString
        let sel = selectedRange()
        let lineRange = nsString.lineRange(for: sel)
        let text = nsString.substring(with: lineRange)
        let lines = text.components(separatedBy: "\n")
        let tabSize = editorTabSize
        let outdented = lines.enumerated().map { index, line in
            if index == lines.count - 1 && line.isEmpty { return line }
            var removed = 0
            var result = line
            while removed < tabSize && result.hasPrefix(" ") {
                result = String(result.dropFirst())
                removed += 1
            }
            if removed == 0 && result.hasPrefix("\t") {
                result = String(result.dropFirst())
            }
            return result
        }.joined(separator: "\n")

        if shouldChangeText(in: lineRange, replacementString: outdented) {
            textStorage?.replaceCharacters(in: lineRange, with: outdented)
            didChangeText()
            setSelectedRange(NSRange(location: lineRange.location, length: (outdented as NSString).length))
        }
    }

    // MARK: - Toggle Comment

    func toggleComment() {
        guard let coordinator = coordinator else { return }
        let style = coordinator.commentStyle()

        let nsString = string as NSString
        let sel = selectedRange()
        let lineRange = nsString.lineRange(for: sel)
        let text = nsString.substring(with: lineRange)
        let lines = text.components(separatedBy: "\n")

        let toggled: String
        switch style {
        case .none:
            return

        case .line(let prefix):
            let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let allCommented = !nonEmptyLines.isEmpty && nonEmptyLines.allSatisfy {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix)
            }

            toggled = lines.map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { return line }

                if allCommented {
                    let leading = line.prefix(while: { $0 == " " || $0 == "\t" })
                    let rest = String(line.dropFirst(leading.count))
                    if rest.hasPrefix(prefix + " ") {
                        return String(leading) + String(rest.dropFirst(prefix.count + 1))
                    } else if rest.hasPrefix(prefix) {
                        return String(leading) + String(rest.dropFirst(prefix.count))
                    }
                    return line
                } else {
                    let leading = line.prefix(while: { $0 == " " || $0 == "\t" })
                    let rest = String(line.dropFirst(leading.count))
                    return String(leading) + prefix + " " + rest
                }
            }.joined(separator: "\n")

        case .block(let open, let close):
            let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let allCommented = !nonEmptyLines.isEmpty && nonEmptyLines.allSatisfy {
                let t = $0.trimmingCharacters(in: .whitespaces)
                return t.hasPrefix(open) && t.hasSuffix(close)
            }

            toggled = lines.map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { return line }

                if allCommented {
                    let leading = line.prefix(while: { $0 == " " || $0 == "\t" })
                    var rest = String(line.dropFirst(leading.count))
                    if rest.hasPrefix(open) {
                        rest = String(rest.dropFirst(open.count))
                    }
                    if rest.hasSuffix(close) {
                        rest = String(rest.dropLast(close.count))
                    }
                    return String(leading) + rest
                } else {
                    let leading = line.prefix(while: { $0 == " " || $0 == "\t" })
                    let rest = String(line.dropFirst(leading.count))
                    return String(leading) + open + rest + close
                }
            }.joined(separator: "\n")
        }

        if shouldChangeText(in: lineRange, replacementString: toggled) {
            textStorage?.replaceCharacters(in: lineRange, with: toggled)
            didChangeText()
            setSelectedRange(NSRange(location: lineRange.location, length: (toggled as NSString).length))
        }
    }

    // MARK: - Auto-close Brackets/Quotes

    func handleAutoClose(_ char: Character) -> Bool {
        let sel = selectedRange()
        let pos = sel.location
        let nsString = string as NSString
        let closers: Set<Character> = [")", "]", "}"]
        let brackets: Set<Character> = ["(", "[", "{"]
        let quotes: Set<Character> = ["\"", "'", "`"]

        // Check if this character type is enabled
        let isBracketChar = brackets.contains(char) || closers.contains(char)
        let isQuoteChar = quotes.contains(char)
        if isBracketChar && !editorAutoCloseBrackets { return false }
        if isQuoteChar && !editorAutoCloseQuotes { return false }

        // Skip over closing bracket if next char matches
        if closers.contains(char) && sel.length == 0 && pos < nsString.length {
            let nextChar = nsString.substring(with: NSRange(location: pos, length: 1))
            if nextChar == String(char) {
                setSelectedRange(NSRange(location: pos + 1, length: 0))
                return true
            }
        }

        // Skip over closing quote if next char matches
        if quotes.contains(char) && sel.length == 0 && pos < nsString.length {
            let nextChar = nsString.substring(with: NSRange(location: pos, length: 1))
            if nextChar == String(char) {
                setSelectedRange(NSRange(location: pos + 1, length: 0))
                return true
            }
        }

        // Auto-insert closing pair
        guard let closer = ZionTextView.autoClosePairs[char] else { return false }

        // For quotes, only auto-close when next char is whitespace, EOL, or closing bracket
        if quotes.contains(char) && pos < nsString.length {
            let nextChar = Character(nsString.substring(with: NSRange(location: pos, length: 1)))
            if !nextChar.isWhitespace && !closers.contains(nextChar) && nextChar != "\n" {
                return false
            }
        }

        if sel.length > 0 {
            // Wrap selection with pair
            let selectedText = nsString.substring(with: sel)
            let wrapped = String(char) + selectedText + String(closer)
            if shouldChangeText(in: sel, replacementString: wrapped) {
                textStorage?.replaceCharacters(in: sel, with: wrapped)
                didChangeText()
                setSelectedRange(NSRange(location: sel.location + 1, length: sel.length))
                return true
            }
        } else {
            let pair = String(char) + String(closer)
            if shouldChangeText(in: NSRange(location: pos, length: 0), replacementString: pair) {
                textStorage?.replaceCharacters(in: NSRange(location: pos, length: 0), with: pair)
                didChangeText()
                setSelectedRange(NSRange(location: pos + 1, length: 0))
                return true
            }
        }
        return false
    }

    // MARK: - Auto-indent on Enter

    func autoIndentNewLine() {
        let nsString = string as NSString
        let sel = selectedRange()
        let pos = sel.location
        let currentLineRange = nsString.lineRange(for: NSRange(location: pos, length: 0))
        let textBeforeCursor = nsString.substring(with: NSRange(location: currentLineRange.location, length: pos - currentLineRange.location))

        let leadingWhitespace = String(textBeforeCursor.prefix(while: { $0 == " " || $0 == "\t" }))
        let trimmedBefore = textBeforeCursor.trimmingCharacters(in: .whitespaces)
        let extraIndent = (trimmedBefore.hasSuffix("{") || trimmedBefore.hasSuffix(":") || trimmedBefore.hasSuffix("(")) ? indentString : ""

        let insertion = "\n" + leadingWhitespace + extraIndent
        insertText(insertion, replacementRange: sel)
    }
}
