import XCTest
@testable import Zion

final class AIClientResponseParsingTests: XCTestCase {

    private let client = AIClient()

    // MARK: - parseReviewFindings

    func testParseReviewFindingsValid() {
        let raw = """
        critical | Sources/App.swift | Memory leak in closure
        warning | Sources/View.swift | Missing accessibility label
        suggestion | Sources/Model.swift | Consider using struct
        """

        let findings = AIClient.parseReviewFindings(raw)

        XCTAssertEqual(findings.count, 3)
        XCTAssertEqual(findings[0].severity, .critical)
        XCTAssertEqual(findings[0].file, "Sources/App.swift")
        XCTAssertEqual(findings[0].message, "Memory leak in closure")
        XCTAssertEqual(findings[1].severity, .warning)
        XCTAssertEqual(findings[2].severity, .suggestion)
    }

    func testParseReviewFindingsWithEvidenceAndTestImpact() {
        let raw = "critical | File.swift | Issue | leaked ref | breaks unit tests"

        let findings = AIClient.parseReviewFindings(raw)

        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings[0].evidence, "leaked ref")
        XCTAssertEqual(findings[0].testImpact, "breaks unit tests")
    }

    func testParseReviewFindingsEmpty() {
        let findings = AIClient.parseReviewFindings("")
        XCTAssertTrue(findings.isEmpty)
    }

    func testParseReviewFindingsMalformed() {
        let raw = """
        This is not a valid finding
        also | not enough
        too | many | pipes | extra | fields | overflow
        """

        let findings = AIClient.parseReviewFindings(raw)
        XCTAssertTrue(findings.isEmpty)
    }

    func testParseReviewFindingsUnknownSeverityDefaultsToSuggestion() {
        let raw = "info | File.swift | Something noted"

        let findings = AIClient.parseReviewFindings(raw)

        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings[0].severity, .suggestion)
    }

    // MARK: - parseDiffExplanation

    func testParseDiffExplanationValid() async {
        let raw = """
        INTENT: Refactor the data layer
        RISKS: May break existing API contracts
        NARRATIVE: This change reorganizes the data access layer.
        SEVERITY: moderate
        """

        let explanation = await client.parseDiffExplanation(raw)

        XCTAssertEqual(explanation.intent, "Refactor the data layer")
        XCTAssertEqual(explanation.risks, "May break existing API contracts")
        XCTAssertEqual(explanation.narrative, "This change reorganizes the data access layer.")
        XCTAssertEqual(explanation.severity, .moderate)
    }

    func testParseDiffExplanationEmpty() async {
        let explanation = await client.parseDiffExplanation("")

        // When intent is empty, falls back to raw text
        XCTAssertEqual(explanation.intent, "")
        XCTAssertEqual(explanation.risks, "No specific risks identified.")
        XCTAssertEqual(explanation.severity, .safe)
    }

    func testParseDiffExplanationFallbackWhenNoMarkers() async {
        let raw = "Just a plain text explanation of the diff."

        let explanation = await client.parseDiffExplanation(raw)

        // Falls back to raw text as intent
        XCTAssertEqual(explanation.intent, raw)
        XCTAssertEqual(explanation.risks, "No specific risks identified.")
        XCTAssertEqual(explanation.severity, .safe)
    }

    func testParseDiffExplanationRiskySeverity() async {
        let raw = """
        INTENT: Delete production database
        SEVERITY: risky
        """

        let explanation = await client.parseDiffExplanation(raw)
        XCTAssertEqual(explanation.severity, .risky)
    }

    // MARK: - parseCommitSuggestions

    func testParseCommitSuggestionsValid() async {
        let raw = """
        MESSAGE: feat(auth): add OAuth2 flow
        FILES: Sources/Auth.swift, Sources/Token.swift

        MESSAGE: fix(ui): correct button alignment
        FILES: Sources/Button.swift
        """

        let suggestions = await client.parseCommitSuggestions(raw)

        XCTAssertEqual(suggestions.count, 2)
        XCTAssertEqual(suggestions[0].message, "feat(auth): add OAuth2 flow")
        XCTAssertEqual(suggestions[0].files, ["Sources/Auth.swift", "Sources/Token.swift"])
        XCTAssertEqual(suggestions[1].message, "fix(ui): correct button alignment")
        XCTAssertEqual(suggestions[1].files, ["Sources/Button.swift"])
    }

    func testParseCommitSuggestionsEmpty() async {
        let suggestions = await client.parseCommitSuggestions("")
        XCTAssertTrue(suggestions.isEmpty)
    }

    func testParseCommitSuggestionsMissingMessage() async {
        let raw = """
        FILES: Sources/App.swift
        """

        let suggestions = await client.parseCommitSuggestions(raw)
        XCTAssertTrue(suggestions.isEmpty)
    }

    // MARK: - parsePRResponse

    func testParsePRResponseWithMarkers() async {
        let raw = """
        TITLE: feat(auth): add OAuth2 support
        BODY:
        This PR adds OAuth2 authentication flow.

        - Adds token refresh logic
        - Adds login screen
        """

        let result = await client.parsePRResponse(raw)

        XCTAssertEqual(result.title, "feat(auth): add OAuth2 support")
        XCTAssertTrue(result.body.contains("OAuth2 authentication flow"))
        XCTAssertTrue(result.body.contains("token refresh logic"))
    }

    func testParsePRResponseWithMarkdownHeading() async {
        let raw = """
        # Add OAuth2 support

        This PR adds OAuth2 authentication flow.

        - Adds token refresh logic
        """

        let result = await client.parsePRResponse(raw)

        XCTAssertEqual(result.title, "Add OAuth2 support")
        XCTAssertTrue(result.body.contains("OAuth2 authentication flow"))
    }

    func testParsePRResponseFirstLineFallback() async {
        let raw = """
        Add OAuth2 support

        This PR adds OAuth2 authentication flow.
        """

        let result = await client.parsePRResponse(raw)

        XCTAssertEqual(result.title, "Add OAuth2 support")
        XCTAssertTrue(result.body.contains("OAuth2 authentication flow"))
    }

    func testParsePRResponseCleansMarkdownFromTitle() async {
        let raw = """
        TITLE: **feat(auth)**: add `OAuth2` support
        BODY:
        Details here.
        """

        let result = await client.parsePRResponse(raw)

        XCTAssertEqual(result.title, "feat(auth): add OAuth2 support")
    }

    func testParsePRResponseTruncatesLongTitle() async {
        let longTitle = "TITLE: " + String(repeating: "a", count: 100)
        let raw = """
        \(longTitle)
        BODY:
        Some body.
        """

        let result = await client.parsePRResponse(raw)

        XCTAssertTrue(result.title.count <= 72)
        XCTAssertTrue(result.title.hasSuffix("..."))
    }

    // MARK: - cleanPRTitle

    func testCleanPRTitleStripsMarkdownHeaders() {
        XCTAssertEqual(AIClient.cleanPRTitle("## My Title"), "My Title")
        XCTAssertEqual(AIClient.cleanPRTitle("### Another Title"), "Another Title")
    }

    func testCleanPRTitleStripsBold() {
        XCTAssertEqual(AIClient.cleanPRTitle("**Bold Title**"), "Bold Title")
    }

    func testCleanPRTitleStripsInlineCode() {
        XCTAssertEqual(AIClient.cleanPRTitle("Fix `bug` in parser"), "Fix bug in parser")
    }

    func testCleanPRTitleTruncatesAt72Characters() {
        let long = String(repeating: "x", count: 100)
        let cleaned = AIClient.cleanPRTitle(long)

        XCTAssertEqual(cleaned.count, 72)
        XCTAssertTrue(cleaned.hasSuffix("..."))
        XCTAssertEqual(cleaned, String(repeating: "x", count: 69) + "...")
    }

    func testCleanPRTitlePreservesShortTitles() {
        XCTAssertEqual(AIClient.cleanPRTitle("Short title"), "Short title")
    }

    func testCleanPRTitleCombinedMarkdown() {
        XCTAssertEqual(AIClient.cleanPRTitle("## **Bold** and `code`"), "Bold and code")
    }
}
