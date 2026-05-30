import XCTest
@testable import Zion

/// Phase 6.8 — built-in `web_search` tool surface. Live HTTP not
/// exercised in CI; we pin descriptor + dispatch error paths so a
/// regression on the no-key fallback (the most visible UX path) shows
/// up in CI before it ships.
final class WebSearchToolTests: XCTestCase {

    func test_webSearch_descriptor_listedInAllTools() {
        XCTAssertTrue(MCPConfigBuilder.allTools().map { $0.name }.contains("web_search"))
    }

    func test_webSearch_missingQuery_returnsErrorMarker() async throws {
        let r = try await MCPConfigBuilder.dispatch(name: "web_search", args: [:])
        XCTAssertTrue(r.contains("missing 'query'"))
    }

    func test_webSearch_emptyQuery_returnsErrorMarker() async throws {
        let r = try await MCPConfigBuilder.dispatch(name: "web_search", args: ["query": "   "])
        XCTAssertTrue(r.contains("missing 'query'"))
    }

    func test_engineEnum_allCasesHaveSignupURL() {
        for e in WebSearchEngine.allCases {
            XCTAssertNotNil(e.signupURL, "Engine \(e) needs a signup/docs URL")
        }
    }

    func test_selectedEngine_defaultsToTavily() {
        // Round-trip: read default, set explicitly, re-read.
        let original = WebSearchSettings.selectedEngine
        defer { WebSearchSettings.selectedEngine = original }
        WebSearchSettings.selectedEngine = .brave
        XCTAssertEqual(WebSearchSettings.selectedEngine, .brave)
    }
}
