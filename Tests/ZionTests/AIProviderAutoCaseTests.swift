import XCTest
@testable import Zion

final class AIProviderAutoCaseTests: XCTestCase {

    func testAutoCaseExists() {
        XCTAssertEqual(AIProvider(rawValue: "auto"), .auto)
    }

    func testAutoInConfigurableProviders() {
        let providers = AIProviderSupport.configurableProviders
        XCTAssertFalse(providers.isEmpty)
        XCTAssertEqual(providers.first, .auto)
    }

    func testAutoIsConnectedAlwaysTrue() {
        let result = AIProviderSupport.isConnected(provider: .auto, loadKey: { _ in nil })
        XCTAssertTrue(result)
    }

    func testAutoLabelNonEmpty() {
        XCTAssertFalse(AIProvider.auto.label.isEmpty)
    }

    func testAutoIconIsWandAndStars() {
        XCTAssertEqual(AIProvider.auto.icon, "wand.and.stars")
    }

    func testAutoDashboardURLIsNil() {
        XCTAssertNil(AIProviderSupport.dashboardURL(for: .auto))
    }
}
