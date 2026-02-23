import XCTest
import AppKit
import SwiftUI
@testable import Zion

final class SourceCodeEditorTests: XCTestCase {
    @MainActor
    func testApplyHighlightingPreservesParagraphStyleAndKern() {
        let text = """
        struct Demo {
            let foo = 1
            func call() { print(foo) }
        }
        """
        let textView = makeTextView(text: text)
        let editor = SourceCodeEditor(
            text: .constant(text),
            theme: .tokyoNight,
            lineSpacing: 2.2,
            fileExtension: "swift",
            letterSpacing: 0.7
        )
        let coordinator = SourceCodeEditor.Coordinator(editor)

        coordinator.applyHighlighting(to: textView, colors: editor.getEditorColors(for: editor.theme))

        let length = (textView.string as NSString).length
        XCTAssertGreaterThan(length, 2)
        let probeIndexes = [0, length / 2, max(0, length - 1)]

        for index in probeIndexes {
            let paragraph = textView.textStorage?.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle
            XCTAssertNotNil(paragraph)
            XCTAssertEqual(paragraph?.lineSpacing ?? -1, 2.2, accuracy: 0.001)

            let kernNumber = textView.textStorage?.attribute(.kern, at: index, effectiveRange: nil) as? NSNumber
            XCTAssertNotNil(kernNumber)
            XCTAssertEqual(kernNumber?.doubleValue ?? -1, 0.7, accuracy: 0.001)
        }
    }

    @MainActor
    func testSearchHighlightsUpdateAcrossTyping() {
        let textView = makeTextView(text: "foo one\nfoo two\nbarfoo\n")
        let editor = SourceCodeEditor(text: .constant(textView.string), theme: .tokyoNight, fileExtension: "swift")
        let coordinator = SourceCodeEditor.Coordinator(editor)

        coordinator.updateSearchHighlights(in: textView, query: "foo", currentIndex: 1)
        XCTAssertEqual(coordinator.searchMatchRanges.count, 3)

        textView.string += "foo three\n"
        coordinator.updateSearchHighlights(in: textView, query: "foo", currentIndex: 2)
        XCTAssertEqual(coordinator.searchMatchRanges.count, 4)

        let currentRange = coordinator.searchMatchRanges[2]
        let previousRange = coordinator.searchMatchRanges[1]
        let currentBackground = textView.textStorage?.attribute(.backgroundColor, at: currentRange.location, effectiveRange: nil) as? NSColor
        let previousBackground = textView.textStorage?.attribute(.backgroundColor, at: previousRange.location, effectiveRange: nil) as? NSColor

        XCTAssertNotNil(currentBackground)
        XCTAssertNotNil(previousBackground)

        let currentAlpha = currentBackground?.usingColorSpace(.deviceRGB)?.alphaComponent
        let previousAlpha = previousBackground?.usingColorSpace(.deviceRGB)?.alphaComponent
        XCTAssertEqual(currentAlpha ?? -1, 0.55, accuracy: 0.02)
        XCTAssertEqual(previousAlpha ?? -1, 0.35, accuracy: 0.02)
    }

    @MainActor
    func testSearchHighlightsClearWhenQueryBecomesEmpty() {
        let textView = makeTextView(text: "foo\nbar\nfoo\n")
        let editor = SourceCodeEditor(text: .constant(textView.string), theme: .tokyoNight, fileExtension: "swift")
        let coordinator = SourceCodeEditor.Coordinator(editor)

        coordinator.updateSearchHighlights(in: textView, query: "foo", currentIndex: 0)
        XCTAssertEqual(coordinator.searchMatchRanges.count, 2)

        coordinator.updateSearchHighlights(in: textView, query: "", currentIndex: 0)
        XCTAssertEqual(coordinator.searchMatchRanges.count, 0)

        let length = (textView.string as NSString).length
        if length > 0 {
            for index in 0..<length {
                let bg = textView.textStorage?.attribute(.backgroundColor, at: index, effectiveRange: nil)
                XCTAssertNil(bg)
            }
        }
    }

    @MainActor
    private func makeTextView(text: String) -> NSTextView {
        let textStorage = NSTextStorage(string: text)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(containerSize: NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isRichText = false
        return textView
    }
}
