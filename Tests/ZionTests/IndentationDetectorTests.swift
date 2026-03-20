import Testing
@testable import Zion

@Suite("IndentationDetector")
struct IndentationDetectorTests {

    @Test("Detects tab indentation")
    func detectTabs() {
        let content = """
        func foo() {
        \tlet x = 1
        \tif true {
        \t\tprint(x)
        \t}
        }
        """
        let result = IndentationDetector.detect(in: content)
        #expect(result != nil)
        #expect(result?.useTabs == true)
    }

    @Test("Detects 2-space indentation")
    func detectTwoSpaces() {
        let content = """
        {
          "name": "test",
          "value": {
            "nested": true
          }
        }
        """
        let result = IndentationDetector.detect(in: content)
        #expect(result != nil)
        #expect(result?.useTabs == false)
        #expect(result?.tabSize == 2)
    }

    @Test("Detects 4-space indentation")
    func detectFourSpaces() {
        let content = """
        func foo() {
            let x = 1
            if true {
                print(x)
            }
        }
        """
        let result = IndentationDetector.detect(in: content)
        #expect(result != nil)
        #expect(result?.useTabs == false)
        #expect(result?.tabSize == 4)
    }

    @Test("Returns nil for no indentation")
    func noIndentation() {
        let content = """
        line one
        line two
        line three
        """
        let result = IndentationDetector.detect(in: content)
        #expect(result == nil)
    }

    @Test("Returns nil for empty content")
    func emptyContent() {
        let result = IndentationDetector.detect(in: "")
        #expect(result == nil)
    }

    @Test("Grid-aligned column: cursor at column 5 with tabSize 4 needs 3 spaces")
    func gridAlignedColumn() {
        let textBeforeCursor = "abcde"
        var column = 0
        let tabSize = 4
        for ch in textBeforeCursor {
            if ch == "\t" {
                column = ((column / tabSize) + 1) * tabSize
            } else {
                column += 1
            }
        }
        let spacesNeeded = tabSize - (column % tabSize)
        #expect(column == 5)
        #expect(spacesNeeded == 3)
    }

    @Test("Grid-aligned column: cursor at column 0 needs full tabSize")
    func gridAlignedAtStart() {
        let textBeforeCursor = ""
        var column = 0
        let tabSize = 4
        for ch in textBeforeCursor {
            if ch == "\t" {
                column = ((column / tabSize) + 1) * tabSize
            } else {
                column += 1
            }
        }
        let spacesNeeded = tabSize - (column % tabSize)
        #expect(column == 0)
        #expect(spacesNeeded == 4)
    }

    @Test("Grid-aligned column: cursor at column 4 (already aligned) needs full tabSize")
    func gridAlignedAtBoundary() {
        let textBeforeCursor = "abcd"
        var column = 0
        let tabSize = 4
        for ch in textBeforeCursor {
            if ch == "\t" {
                column = ((column / tabSize) + 1) * tabSize
            } else {
                column += 1
            }
        }
        let spacesNeeded = tabSize - (column % tabSize)
        #expect(column == 4)
        #expect(spacesNeeded == 4)
    }

    @Test("Grid-aligned column: tab character in text expands correctly")
    func gridAlignedWithTab() {
        let textBeforeCursor = "a\tb"
        var column = 0
        let tabSize = 4
        for ch in textBeforeCursor {
            if ch == "\t" {
                column = ((column / tabSize) + 1) * tabSize
            } else {
                column += 1
            }
        }
        // "a" = col 1, \t expands to col 4, "b" = col 5
        let spacesNeeded = tabSize - (column % tabSize)
        #expect(column == 5)
        #expect(spacesNeeded == 3)
    }
}
