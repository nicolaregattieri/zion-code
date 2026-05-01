import AppKit
import SwiftUI
import XCTest
@testable import Zion

final class EditorThemeTests: XCTestCase {
    func testEveryThemeHasEditorAndTerminalPalette() {
        for theme in EditorTheme.allCases {
            XCTAssertFalse(theme.label.isEmpty, "\(theme.rawValue) should have a display label")
            XCTAssertEqual(theme.terminalPalette.ansiColors.count, 16, "\(theme.rawValue) should define 16 ANSI colors")
            XCTAssertGreaterThan(theme.colors.nsBackground.alphaComponent, 0, "\(theme.rawValue) should define an editor background")
            XCTAssertGreaterThan(theme.colors.nsText.alphaComponent, 0, "\(theme.rawValue) should define editor text")
        }
    }

    func testLightAppearanceThemesAreExplicitlyClassified() {
        let lightThemes = Set(EditorTheme.allCases.filter(\.isLightAppearance))

        XCTAssertEqual(lightThemes, [.githubLight, .everforestProLight, .colorblindLight])
    }

    @MainActor
    func testSourceCodeEditorColorsCoverEveryTheme() {
        let editor = SourceCodeEditor(text: .constant("let value = 1"), theme: .dracula, fileExtension: "swift")

        for theme in EditorTheme.allCases {
            let colors = editor.getEditorColors(for: theme)

            XCTAssertGreaterThan(colors.background.alphaComponent, 0, "\(theme.rawValue) should define AppKit background")
            XCTAssertGreaterThan(colors.text.alphaComponent, 0, "\(theme.rawValue) should define AppKit text")
            XCTAssertGreaterThan(colors.call.alphaComponent, 0, "\(theme.rawValue) should define call highlighting")
        }
    }
}
