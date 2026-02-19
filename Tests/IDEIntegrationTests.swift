import XCTest
import Foundation
@testable import Zion

final class IDEIntegrationTests: XCTestCase {
    func testEditorEnumMapping() {
        XCTAssertEqual(ExternalEditor.vscode.rawValue, "com.microsoft.VSCode")
        XCTAssertEqual(ExternalEditor.cursor.rawValue, "com.todesktop.230313mzl4w4u92")
    }
    
    func testAppPathValidation() {
        let ws = NSWorkspace.shared
        // This test only runs on machines with VS Code installed
        if let url = ws.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
    }
}
