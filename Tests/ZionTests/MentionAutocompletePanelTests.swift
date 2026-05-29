import XCTest
@testable import Zion

/// Phase 4 — autocomplete token list contract.
/// Locks down criteria 11b (longest-prefix disambiguation) and 12 (Phase-4
/// tokens surfaced in the suggestion list).
@MainActor
final class MentionAutocompletePanelTests: XCTestCase {

    func test_tokenList_containsDiffPrFolder() {
        let tokens = MentionAutocompletePanel.availableTokens
        XCTAssertTrue(tokens.contains("@file"))
        XCTAssertTrue(tokens.contains("@folder"))
        XCTAssertTrue(tokens.contains("@selection"))
        XCTAssertTrue(tokens.contains("@web"))
        XCTAssertTrue(tokens.contains("@diff"))
        XCTAssertTrue(tokens.contains("@pr"))
    }

    func test_longestPrefixMatch_filevsFolder() {
        let ranked = MentionAutocompletePanel.rankedTokens(matching: "fo")
        let foldersIdx = ranked.firstIndex(of: "@folder")
        let fileIdx = ranked.firstIndex(of: "@file")
        XCTAssertNotNil(foldersIdx)
        XCTAssertNotNil(fileIdx)
        XCTAssertLessThan(foldersIdx!, fileIdx!, "@folder must outrank @file when the partial is 'fo'")
    }

    func test_emptyPartial_returnsAllTokens() {
        let ranked = MentionAutocompletePanel.rankedTokens(matching: "")
        XCTAssertEqual(ranked, MentionAutocompletePanel.availableTokens)
    }
}
