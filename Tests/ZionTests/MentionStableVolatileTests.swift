// MentionStableVolatileTests.swift — Tests for MentionPayload stable/volatile split.

import XCTest
@testable import Zion

final class MentionStableVolatileTests: XCTestCase {

    // MARK: 1. MentionPayload.empty has both fields empty

    func test_payload_has_stable_volatile_fields() {
        let payload = MentionPayload.empty
        XCTAssertEqual(payload.stableContext, "")
        XCTAssertEqual(payload.volatileContext, "")
    }

    // MARK: 2. systemContext concatenates both when both present

    func test_systemContext_concatenates_both_when_present() {
        let payload = MentionPayload(
            stableContext: "S",
            volatileContext: "V",
            totalBytes: 0,
            perFileBreakdown: [],
            mentions: []
        )
        XCTAssertEqual(payload.systemContext, "S\n\nV")
    }

    // MARK: 3. systemContext returns volatile when stable is empty

    func test_systemContext_returns_volatile_when_stable_empty() {
        let payload = MentionPayload(
            stableContext: "",
            volatileContext: "V",
            totalBytes: 0,
            perFileBreakdown: [],
            mentions: []
        )
        XCTAssertEqual(payload.systemContext, "V")
    }

    // MARK: 4. systemContext returns stable when volatile is empty

    func test_systemContext_returns_stable_when_volatile_empty() {
        let payload = MentionPayload(
            stableContext: "S",
            volatileContext: "",
            totalBytes: 0,
            perFileBreakdown: [],
            mentions: []
        )
        XCTAssertEqual(payload.systemContext, "S")
    }

    // MARK: 5. expand populates volatileContext for @file; stableContext is always empty from resolver

    func test_expand_populates_volatile_for_at_file() async throws {
        let mock = MockMentionToolClient(responses: ["read_file": "FILE BODY"])
        let resolver = MentionResolver(toolClient: mock)

        let payload = await resolver.expand(message: "check @file Foo.swift")

        XCTAssertEqual(payload.stableContext, "",
                       "MentionResolver must leave stableContext empty (ChatService fills it)")
        XCTAssertTrue(payload.volatileContext.contains("FILE BODY"),
                      "volatileContext must contain the resolved file body")
    }

    // MARK: 6. expand with no mentions returns empty payload

    func test_expand_with_no_mentions_returns_empty_payload() async throws {
        let mock = MockMentionToolClient()
        let resolver = MentionResolver(toolClient: mock)

        let payload = await resolver.expand(message: "plain text with no mentions")

        XCTAssertEqual(payload.stableContext, "")
        XCTAssertEqual(payload.volatileContext, "")
        XCTAssertEqual(payload.totalBytes, 0)
        XCTAssertTrue(payload.mentions.isEmpty)
    }
}
