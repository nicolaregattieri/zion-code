import XCTest
@testable import Zion

/// Pins the chat fixes for Auto mode: per-provider API keys, the output
/// token budget, truncation detection, and the error strings the chat
/// shows (they used to render as raw keys like `chat.error.generic`).
final class ChatAutoRoutingFixesTests: XCTestCase {

    // MARK: - API key resolution

    func testAutoLoadsKeyForResolvedProvider() {
        // The composer passes the key stored for `.auto`, which is empty.
        let key = ChatService.resolveAPIKey(
            for: .anthropic,
            requested: .auto,
            passedKey: "",
            loader: { $0 == .anthropic ? "sk-ant-test" : nil }
        )
        XCTAssertEqual(key, "sk-ant-test")
    }

    func testExplicitProviderKeepsPassedKey() {
        let key = ChatService.resolveAPIKey(
            for: .openai,
            requested: .openai,
            passedKey: "sk-passed",
            loader: { _ in XCTFail("loader must not run when the passed key matches"); return nil }
        )
        XCTAssertEqual(key, "sk-passed")
    }

    func testExplicitProviderWithEmptyKeyNeverHitsKeychain() {
        // Reading the Keychain can block on a locked keychain (CI runners),
        // so an explicit provider must keep the caller's key as is.
        let key = ChatService.resolveAPIKey(
            for: .gemini,
            requested: .gemini,
            passedKey: "",
            loader: { _ in XCTFail("loader must not run for an explicit provider"); return nil }
        )
        XCTAssertEqual(key, "")
    }

    func testAutoResolvingToCLIOrLocalNeverHitsKeychain() {
        for resolved in [AIProvider.claudeCLI, .codexCLI, .local] {
            let key = ChatService.resolveAPIKey(
                for: resolved,
                requested: .auto,
                passedKey: "",
                loader: { _ in XCTFail("loader must not run for \(resolved)"); return nil }
            )
            XCTAssertEqual(key, "", "\(resolved) needs no API key")
        }
    }

    func testFallbackHopNeverReusesPreviousProvidersKey() {
        // Hop from Anthropic to OpenAI: the Anthropic key must not leak over.
        let key = ChatService.resolveAPIKey(
            for: .openai,
            requested: .auto,
            passedKey: "sk-ant-previous",
            loader: { $0 == .openai ? "sk-openai" : nil }
        )
        XCTAssertEqual(key, "sk-openai")
    }

    func testMissingKeyResolvesToEmptyString() {
        let key = ChatService.resolveAPIKey(
            for: .gemini,
            requested: .auto,
            passedKey: "",
            loader: { _ in nil }
        )
        XCTAssertEqual(key, "")
    }

    // MARK: - Output budget

    func testChatOutputBudgetIsNotTheOld2048Cap() {
        XCTAssertGreaterThanOrEqual(ChatService.chatMaxOutputTokens, 8192)
    }

    // MARK: - Truncation detection

    func testAnthropicMaxTokensStopIsFlaggedAsTruncated() {
        let data = Data(#"{"type":"message_delta","delta":{"stop_reason":"max_tokens"}}"#.utf8)
        let chunk = AIClient.parseAnthropicSSEEvent(eventName: "message_delta", data: data)
        XCTAssertNotNil(chunk)
        XCTAssertEqual(chunk?.truncated, true)
        XCTAssertEqual(chunk?.text, "")
        XCTAssertEqual(chunk?.done, false)
    }

    func testAnthropicEndTurnIsNotTruncated() {
        let data = Data(#"{"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#.utf8)
        XCTAssertNil(AIClient.parseAnthropicSSEEvent(eventName: "message_delta", data: data))
    }

    func testOpenAILengthFinishIsFlaggedAsTruncated() {
        let line = Data(#"data: {"choices":[{"delta":{},"finish_reason":"length"}]}"#.utf8)
        let chunk = AIClient.parseOpenAISSELine(line)
        XCTAssertEqual(chunk?.truncated, true)
        XCTAssertEqual(chunk?.done, true)
    }

    func testOpenAIStopFinishIsNotTruncated() {
        let line = Data(#"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#.utf8)
        let chunk = AIClient.parseOpenAISSELine(line)
        XCTAssertEqual(chunk?.truncated, false)
        XCTAssertEqual(chunk?.done, true)
    }

    // MARK: - Localization coverage

    private let locales = ["en", "pt-BR", "es"]

    private func loadStrings(locale: String) -> [String: String] {
        guard let path = Bundle.zionResources.path(
            forResource: "Localizable",
            ofType: "strings",
            inDirectory: nil,
            forLocalization: locale
        ), let dict = NSDictionary(contentsOfFile: path) as? [String: String] else {
            XCTFail("Could not load Localizable.strings for \(locale)")
            return [:]
        }
        return dict
    }

    func testNewChatStringsExistInAllLocales() {
        let keys = [
            "chat.error.generic",
            "ai.error.rateLimited",
            "ai.error.rateLimited.delay",
            "ai.error.networkFailure",
            "chat.routing.allProvidersExhausted",
            "chat.routing.switched",
            "chat.response.truncated",
        ]
        for locale in locales {
            let dict = loadStrings(locale: locale)
            for key in keys {
                XCTAssertNotNil(dict[key], "\(key) missing in \(locale)")
            }
            XCTAssertEqual(dict["chat.routing.switched"]?.components(separatedBy: "%@").count, 3,
                           "chat.routing.switched needs two %@ in \(locale)")
        }
    }

    /// Every literal `L10n("key")` in Sources must exist in every locale;
    /// otherwise the UI shows the raw key.
    func testEveryLiteralL10nKeyInSourcesIsDefined() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ZionTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let sourcesDir = repoRoot.appendingPathComponent("Sources/Zion")
        guard let enumerator = FileManager.default.enumerator(at: sourcesDir, includingPropertiesForKeys: nil) else {
            XCTFail("Could not enumerate \(sourcesDir.path)")
            return
        }
        let regex = try NSRegularExpression(pattern: #"L10n\("([A-Za-z0-9_.]+)""#)
        var usedKeys = Set<String>()
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                if let r = Range(match.range(at: 1), in: text) {
                    usedKeys.insert(String(text[r]))
                }
            }
        }
        XCTAssertFalse(usedKeys.isEmpty, "Scanner found no L10n keys; path is probably wrong")
        for locale in locales {
            let dict = loadStrings(locale: locale)
            let missing = usedKeys.filter { dict[$0] == nil }.sorted()
            XCTAssertTrue(missing.isEmpty, "Missing in \(locale): \(missing.joined(separator: ", "))")
        }
    }
}
