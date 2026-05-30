import XCTest
@testable import Zion

/// Tool-affinity routing: when the user turn looks tool-heavy, bias the
/// Auto-mode lane so we don't ask a cheap-tier model to drive a tool
/// loop it cannot handle.
final class ToolAffinityLaneTests: XCTestCase {

    func test_directToolNameMention_returnsGeneral() {
        XCTAssertEqual(
            ChatService.toolAffinityLane(text: "please run ctx_search on auth", userToolNames: ["ctx_search", "ctx_execute"]),
            .general
        )
    }

    func test_reasoningVerb_returnsReasoning() {
        XCTAssertEqual(
            ChatService.toolAffinityLane(text: "debug why this test fails", userToolNames: []),
            .reasoning
        )
    }

    func test_actionVerb_returnsGeneral() {
        XCTAssertEqual(
            ChatService.toolAffinityLane(text: "search the docs for OAuth", userToolNames: []),
            .general
        )
    }

    func test_reasoningBeatsAction_whenBothPresent() {
        // "debug" + "search" — reasoning takes precedence by design.
        XCTAssertEqual(
            ChatService.toolAffinityLane(text: "debug the search flow step by step", userToolNames: []),
            .reasoning
        )
    }

    func test_chitchat_returnsNil() {
        XCTAssertNil(ChatService.toolAffinityLane(text: "hi how are you", userToolNames: ["ctx_search"]))
    }

    func test_emptyToolList_stillUsesVerbs() {
        XCTAssertEqual(
            ChatService.toolAffinityLane(text: "analyze this stacktrace", userToolNames: []),
            .general
        )
    }

    func test_toolNameMatchIsCaseInsensitive() {
        XCTAssertEqual(
            ChatService.toolAffinityLane(text: "Use CTX_SEARCH please", userToolNames: ["ctx_search"]),
            .general
        )
    }
}
