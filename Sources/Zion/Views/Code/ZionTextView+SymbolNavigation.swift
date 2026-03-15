import AppKit

extension ZionTextView {

    // MARK: - Symbol Navigation

    func requestDefinitionFromCaret() {
        guard let query = navigationQueryFromCaret() else {
            NSSound.beep()
            return
        }
        onRequestDefinition?(query)
    }

    func requestReferencesFromCaret() {
        guard let query = navigationQueryFromCaret() else {
            NSSound.beep()
            return
        }
        onRequestReferences?(query)
    }

    func navigationQueryFromCaret() -> EditorSymbolQuery? {
        guard let range = currentSymbolRange() else { return nil }
        return navigationQuery(for: range)
    }

    func navigationQuery(at windowPoint: NSPoint) -> EditorSymbolQuery? {
        guard let index = characterIndex(at: convert(windowPoint, from: nil)),
              let range = symbolRange(at: index) else {
            return nil
        }
        setSelectedRange(range)
        return navigationQuery(for: range)
    }

    func navigationQuery(for symbolRange: NSRange) -> EditorSymbolQuery? {
        guard symbolRange.length > 0 else { return nil }
        let nsString = string as NSString
        let symbol = nsString.substring(with: symbolRange)
        guard !symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let lineRange = nsString.lineRange(for: symbolRange)
        let lineText = nsString.substring(with: lineRange)
        return EditorSymbolQuery(symbol: symbol, currentFilePath: currentFilePath, lineText: lineText)
    }

    func currentSymbolRange() -> NSRange? {
        let sel = selectedRange()
        let nsString = string as NSString
        guard nsString.length > 0 else { return nil }

        if sel.length > 0 {
            let selected = nsString.substring(with: sel).trimmingCharacters(in: .whitespacesAndNewlines)
            return selected.isEmpty ? nil : sel
        }

        let caret = min(sel.location, max(0, nsString.length - 1))
        if let direct = symbolRange(at: caret) {
            return direct
        }
        if caret > 0 {
            return symbolRange(at: caret - 1)
        }
        return nil
    }

    func symbolRange(at index: Int) -> NSRange? {
        let nsString = string as NSString
        guard index >= 0, index < nsString.length else { return nil }
        let charset = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_$"))

        func isSymbolChar(at idx: Int) -> Bool {
            guard idx >= 0, idx < nsString.length else { return false }
            let scalar = nsString.substring(with: NSRange(location: idx, length: 1)).unicodeScalars.first
            return scalar.map { charset.contains($0) } ?? false
        }

        guard isSymbolChar(at: index) else { return nil }

        var start = index
        var end = index
        while start > 0 && isSymbolChar(at: start - 1) { start -= 1 }
        while end + 1 < nsString.length && isSymbolChar(at: end + 1) { end += 1 }
        return NSRange(location: start, length: end - start + 1)
    }

    func characterIndex(at localPoint: NSPoint) -> Int? {
        guard let layoutManager = layoutManager, let container = textContainer else { return nil }
        var point = localPoint
        point.x -= textContainerOrigin.x
        point.y -= textContainerOrigin.y
        guard point.x >= 0, point.y >= 0 else { return nil }

        let glyphIndex = layoutManager.glyphIndex(for: point, in: container)
        return layoutManager.characterIndexForGlyph(at: glyphIndex)
    }

    // MARK: - Select Next Occurrence (Cmd+D)

    func selectNextOccurrence() {
        let nsString = string as NSString
        guard nsString.length > 0 else { return }

        let existing = selectedRanges.map(\.rangeValue)
            .filter { $0.location != NSNotFound }
        let meaningfulSelections = existing.filter { $0.length > 0 }

        if meaningfulSelections.isEmpty {
            if let seed = currentSymbolRange() {
                setSelectedRange(seed)
                scrollRangeToVisible(seed)
                let value = nsString.substring(with: seed).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    onFindSeedFromMultiSelect?(value)
                }
            } else {
                NSSound.beep()
            }
            return
        }

        guard let seed = meaningfulSelections.last else {
            NSSound.beep()
            return
        }

        let selectedText = nsString.substring(with: seed)
        guard !selectedText.isEmpty else {
            NSSound.beep()
            return
        }
        let normalizedSelection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedSelection.isEmpty {
            onFindSeedFromMultiSelect?(normalizedSelection)
        }

        let enforceBoundary = selectedText.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
        if let nextRange = findNextMatch(
            for: selectedText,
            from: NSMaxRange(seed),
            wrapToStartAt: seed.location,
            enforceBoundary: enforceBoundary,
            excluding: meaningfulSelections
        ) {
            var merged = meaningfulSelections
            merged.append(nextRange)
            selectedRanges = merged.map(NSValue.init(range:))
            scrollRangeToVisible(nextRange)
            return
        }

        NSSound.beep()
    }

    func findNextMatch(
        for needle: String,
        from startLocation: Int,
        wrapToStartAt wrapLimit: Int,
        enforceBoundary: Bool,
        excluding ranges: [NSRange]
    ) -> NSRange? {
        let nsString = string as NSString
        let length = nsString.length
        guard length > 0 else { return nil }

        func firstMatch(in range: NSRange) -> NSRange? {
            guard range.length > 0 else { return nil }
            var searchLocation = range.location
            while searchLocation < NSMaxRange(range) {
                let searchRange = NSRange(location: searchLocation, length: NSMaxRange(range) - searchLocation)
                let found = nsString.range(of: needle, options: [], range: searchRange)
                if found.location == NSNotFound {
                    return nil
                }
                searchLocation = NSMaxRange(found)
                if ranges.contains(where: { $0.location == found.location && $0.length == found.length }) {
                    continue
                }
                if enforceBoundary && !isBoundaryMatch(found) {
                    continue
                }
                return found
            }
            return nil
        }

        if let forward = firstMatch(in: NSRange(location: max(0, startLocation), length: max(0, length - startLocation))) {
            return forward
        }
        if wrapLimit > 0 {
            return firstMatch(in: NSRange(location: 0, length: min(wrapLimit, length)))
        }
        return nil
    }

    func isBoundaryMatch(_ range: NSRange) -> Bool {
        let nsString = string as NSString
        let leftOK: Bool
        if range.location == 0 {
            leftOK = true
        } else {
            let prev = Character(nsString.substring(with: NSRange(location: range.location - 1, length: 1)))
            leftOK = !(prev.isLetter || prev.isNumber || prev == "_")
        }

        let rightOK: Bool
        let rightIndex = NSMaxRange(range)
        if rightIndex >= nsString.length {
            rightOK = true
        } else {
            let next = Character(nsString.substring(with: NSRange(location: rightIndex, length: 1)))
            rightOK = !(next.isLetter || next.isNumber || next == "_")
        }
        return leftOK && rightOK
    }

    // MARK: - Find Seed Helpers

    func currentFindSeedFromSelection() -> String? {
        let range = selectedRange()
        guard range.location != NSNotFound, range.length > 0 else { return nil }
        let nsString = string as NSString
        guard NSMaxRange(range) <= nsString.length else { return nil }
        let selectedText = nsString.substring(with: range)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedText.isEmpty else { return nil }
        guard !selectedText.contains("\n"), !selectedText.contains("\r") else { return nil }
        return selectedText
    }

    func emitFindSeedFromSelection() {
        onFindSeedFromMultiSelect?(currentFindSeedFromSelection() ?? "")
    }
}
