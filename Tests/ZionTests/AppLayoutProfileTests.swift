import XCTest
@testable import Zion

final class AppLayoutProfileTests: XCTestCase {
    func testShellLayoutProfileCollapsesSidebarInCompactWidth() {
        let profile = AppShellLayoutProfile(width: DesignSystem.Layout.compactShellWidthThreshold - 1)

        XCTAssertTrue(profile.prefersCollapsedPrimarySidebar)
        XCTAssertFalse(profile.usesCompactToolbar)
        XCTAssertFalse(profile.usesCompactStatusBar)
    }

    func testShellLayoutProfileCompactsChromeAtToolbarThreshold() {
        let profile = AppShellLayoutProfile(width: DesignSystem.Layout.compactToolbarWidthThreshold - 1)

        XCTAssertTrue(profile.usesCompactToolbar)
        XCTAssertTrue(profile.usesCompactStatusBar)
    }

    func testShellLayoutProfileKeepsFullChromeInWideWidth() {
        let profile = AppShellLayoutProfile(width: DesignSystem.Layout.compactShellWidthThreshold + 120)

        XCTAssertFalse(profile.prefersCollapsedPrimarySidebar)
        XCTAssertFalse(profile.usesCompactToolbar)
        XCTAssertFalse(profile.usesCompactStatusBar)
    }

    func testCodeScreenLayoutProfileSwitchesToVerticalPreviewInCompactWidth() {
        let profile = CodeScreenLayoutProfile(width: DesignSystem.Layout.verticalMarkdownPreviewWidthThreshold - 1)

        XCTAssertTrue(profile.prefersVerticalMarkdownPreview)
    }

    func testCodeScreenLayoutProfileAutoCollapsesFileBrowserInVeryTightWidth() {
        let profile = CodeScreenLayoutProfile(width: DesignSystem.Layout.autoCollapseFileBrowserWidthThreshold - 1)

        XCTAssertTrue(profile.prefersAutoCollapsedFileBrowser)
    }
}
