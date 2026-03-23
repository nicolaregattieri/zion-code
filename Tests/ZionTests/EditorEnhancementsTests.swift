import XCTest
@testable import Zion

final class EditorEnhancementsTests: XCTestCase {

    // MARK: - Trim Trailing Whitespace

    func testTrimTrailingWhitespace_removesTrailingSpaces() {
        let input = "hello   \nworld  \n  indented  \n"
        let expected = "hello\nworld\n  indented\n"
        let result = trimTrailingWhitespace(input)
        XCTAssertEqual(result, expected)
    }

    func testTrimTrailingWhitespace_removesTrailingTabs() {
        let input = "hello\t\t\nworld\t\n"
        let expected = "hello\nworld\n"
        let result = trimTrailingWhitespace(input)
        XCTAssertEqual(result, expected)
    }

    func testTrimTrailingWhitespace_preservesLeadingWhitespace() {
        let input = "    indented\n\ttabbed\n"
        let result = trimTrailingWhitespace(input)
        XCTAssertEqual(result, input) // no trailing ws, nothing changes
    }

    func testTrimTrailingWhitespace_handlesEmptyLines() {
        let input = "line1\n\n   \nline2\n"
        let expected = "line1\n\n\nline2\n"
        let result = trimTrailingWhitespace(input)
        XCTAssertEqual(result, expected)
    }

    func testTrimTrailingWhitespace_emptyString() {
        XCTAssertEqual(trimTrailingWhitespace(""), "")
    }

    func testTrimTrailingWhitespace_singleLineNoNewline() {
        let input = "hello   "
        let expected = "hello"
        let result = trimTrailingWhitespace(input)
        XCTAssertEqual(result, expected)
    }

    // MARK: - File Tree Filtering

    func testFilterFileTree_matchesFileByName() {
        let file = FileItem(url: URL(fileURLWithPath: "/repo/main.swift"), isDirectory: false, children: nil)
        let result = filterFileTree(file, query: "main")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "main.swift")
    }

    func testFilterFileTree_excludesNonMatchingFile() {
        let file = FileItem(url: URL(fileURLWithPath: "/repo/other.swift"), isDirectory: false, children: nil)
        let result = filterFileTree(file, query: "main")
        XCTAssertNil(result)
    }

    func testFilterFileTree_includesParentOfMatchingChild() {
        let child = FileItem(url: URL(fileURLWithPath: "/repo/src/main.swift"), isDirectory: false, children: nil)
        let parent = FileItem(url: URL(fileURLWithPath: "/repo/src"), isDirectory: true, children: [child])
        let result = filterFileTree(parent, query: "main")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.children?.count, 1)
    }

    func testFilterFileTree_excludesEmptyFolder() {
        let child = FileItem(url: URL(fileURLWithPath: "/repo/src/other.swift"), isDirectory: false, children: nil)
        let parent = FileItem(url: URL(fileURLWithPath: "/repo/src"), isDirectory: true, children: [child])
        let result = filterFileTree(parent, query: "main")
        XCTAssertNil(result)
    }

    func testFilterFileTree_caseInsensitive() {
        let file = FileItem(url: URL(fileURLWithPath: "/repo/README.md"), isDirectory: false, children: nil)
        let result = filterFileTree(file, query: "readme")
        XCTAssertNotNil(result)
    }

    func testFilterFileTree_deepNesting() {
        let deep = FileItem(url: URL(fileURLWithPath: "/repo/a/b/c/target.swift"), isDirectory: false, children: nil)
        let c = FileItem(url: URL(fileURLWithPath: "/repo/a/b/c"), isDirectory: true, children: [deep])
        let b = FileItem(url: URL(fileURLWithPath: "/repo/a/b"), isDirectory: true, children: [c])
        let a = FileItem(url: URL(fileURLWithPath: "/repo/a"), isDirectory: true, children: [b])
        let result = filterFileTree(a, query: "target")
        XCTAssertNotNil(result)
        XCTAssertNotNil(result?.children?.first?.children?.first?.children?.first)
    }

    // MARK: - Search Regex Building

    func testBuildSearchRegex_plainText() {
        let regex = buildTestSearchRegex(query: "hello", matchCase: false, isRegex: false, wholeWord: false)
        XCTAssertNotNil(regex)
        let text = "Hello World hello"
        let matches = regex!.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
        XCTAssertEqual(matches.count, 2) // case insensitive
    }

    func testBuildSearchRegex_matchCase() {
        let regex = buildTestSearchRegex(query: "Hello", matchCase: true, isRegex: false, wholeWord: false)
        XCTAssertNotNil(regex)
        let text = "Hello World hello"
        let matches = regex!.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
        XCTAssertEqual(matches.count, 1)
    }

    func testBuildSearchRegex_wholeWord() {
        let regex = buildTestSearchRegex(query: "he", matchCase: false, isRegex: false, wholeWord: true)
        XCTAssertNotNil(regex)
        let text = "he hello the"
        let matches = regex!.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
        XCTAssertEqual(matches.count, 1) // only standalone "he"
    }

    func testBuildSearchRegex_regexMode() {
        let regex = buildTestSearchRegex(query: "\\d+", matchCase: false, isRegex: true, wholeWord: false)
        XCTAssertNotNil(regex)
        let text = "abc 123 def 456"
        let matches = regex!.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
        XCTAssertEqual(matches.count, 2)
    }

    func testBuildSearchRegex_invalidRegex() {
        let regex = buildTestSearchRegex(query: "[invalid", matchCase: false, isRegex: true, wholeWord: false)
        XCTAssertNil(regex)
    }

    // MARK: - Localization Keys Exist

    func testNewLocalizationKeysExist() {
        let keys = [
            "settings.editor.trimTrailingWhitespace",
            "settings.editor.renderWhitespace",
            "settings.editor.renderWhitespace.none",
            "settings.editor.renderWhitespace.boundary",
            "settings.editor.renderWhitespace.trailing",
            "settings.editor.renderWhitespace.all",
            "settings.editor.topPadding",
            "settings.editor.scrollPastEnd",
            "settings.editor.font.system",
            "settings.editor.font.installed",
            "editor.search.matchCase",
            "editor.search.wholeWord",
            "editor.search.regex",
            "fileBrowser.filter",
            "fileBrowser.filter.placeholder"
        ]
        for key in keys {
            let value = L10n(key)
            XCTAssertNotEqual(value, key, "L10n key '\(key)' returned raw key -- missing translation")
            XCTAssertFalse(value.isEmpty, "L10n key '\(key)' returned empty string")
        }
    }

    // MARK: - MonospaceFontResolver

    func testSystemFontsAlwaysAvailable() {
        // These ship with macOS
        XCTAssertTrue(MonospaceFontResolver.isAvailable(name: "SF Mono"))
        XCTAssertTrue(MonospaceFontResolver.isAvailable(name: "Menlo"))
        XCTAssertTrue(MonospaceFontResolver.isAvailable(name: "Monaco"))
        XCTAssertTrue(MonospaceFontResolver.isAvailable(name: "Courier"))
    }

    func testUnknownFontNotAvailable() {
        XCTAssertFalse(MonospaceFontResolver.isAvailable(name: "NonExistentFont12345"))
    }

    // MARK: - Helpers (delegate to production code)

    private func trimTrailingWhitespace(_ content: String) -> String {
        EditorHelpers.trimTrailingWhitespace(content)
    }

    private func filterFileTree(_ item: FileItem, query: String) -> FileItem? {
        EditorHelpers.filterFileTree(item, query: query)
    }

    private func buildTestSearchRegex(query: String, matchCase: Bool, isRegex: Bool, wholeWord: Bool) -> NSRegularExpression? {
        EditorHelpers.buildSearchRegex(query: query, matchCase: matchCase, isRegex: isRegex, wholeWord: wholeWord)
    }
}
