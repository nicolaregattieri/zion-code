import XCTest
@testable import Zion

final class AIProviderSupportToolsTests: XCTestCase {

    // MARK: - AIProvider.supportsToolCalling (non-local)

    func testAnthropicSupportsToolCalling() {
        XCTAssertTrue(AIProvider.anthropic.supportsToolCalling)
    }

    func testOpenAISupportsToolCalling() {
        XCTAssertTrue(AIProvider.openai.supportsToolCalling)
    }

    func testGeminiDoesNotSupportToolCalling() {
        XCTAssertFalse(AIProvider.gemini.supportsToolCalling)
    }

    func testNoneDoesNotSupportToolCalling() {
        XCTAssertFalse(AIProvider.none.supportsToolCalling)
    }

    // MARK: - AIProvider.local.supportsToolCalling via UserDefaults

    func testLocalSupportsToolCallingWhenModelIsWhitelisted() {
        let suite = UserDefaults(suiteName: "AIProviderSupportToolsTests_whitelist")!
        suite.removePersistentDomain(forName: "AIProviderSupportToolsTests_whitelist")

        let config = LocalLLMConfig(modelName: "qwen3-coder:30b")
        let data = try! JSONEncoder().encode(config)
        suite.set(data, forKey: UserDefaultsKeys.AI.localConfig)

        // Verify via the function directly (avoids global UserDefaults side-effects)
        XCTAssertTrue(AIProviderSupport.localModelSupportsTools(config.modelName))
        suite.removePersistentDomain(forName: "AIProviderSupportToolsTests_whitelist")
    }

    func testLocalDoesNotSupportToolCallingWhenModelIsUnknown() {
        XCTAssertFalse(AIProviderSupport.localModelSupportsTools("phi-2"))
    }

    // MARK: - localModelSupportsTools whitelist

    func testQwen3CoderMatches() {
        XCTAssertTrue(AIProviderSupport.localModelSupportsTools("qwen3-coder:30b"))
    }

    func testQwen25CoderMatches() {
        XCTAssertTrue(AIProviderSupport.localModelSupportsTools("qwen2.5-coder:7b"))
    }

    func testLlama33Matches() {
        XCTAssertTrue(AIProviderSupport.localModelSupportsTools("llama-3.3-70b"))
    }

    func testLlama39Matches() {
        XCTAssertTrue(AIProviderSupport.localModelSupportsTools("llama-3.9-8b"))
    }

    func testMistralLargeMatches() {
        XCTAssertTrue(AIProviderSupport.localModelSupportsTools("mistral-large-2407"))
    }

    func testDeepseekV3Matches() {
        XCTAssertTrue(AIProviderSupport.localModelSupportsTools("deepseek-v3"))
    }

    func testGptOssMatches() {
        XCTAssertTrue(AIProviderSupport.localModelSupportsTools("gpt-oss"))
    }

    func testGlm4Matches() {
        XCTAssertTrue(AIProviderSupport.localModelSupportsTools("glm-4-9b"))
    }

    func testCaseInsensitiveMatch() {
        XCTAssertTrue(AIProviderSupport.localModelSupportsTools("QWEN3-CODER:latest"))
        XCTAssertTrue(AIProviderSupport.localModelSupportsTools("Mistral-Large"))
    }

    func testPhi2DoesNotMatch() {
        XCTAssertFalse(AIProviderSupport.localModelSupportsTools("phi-2"))
    }

    func testGpt35DoesNotMatch() {
        XCTAssertFalse(AIProviderSupport.localModelSupportsTools("gpt-3.5"))
    }

    func testEmptyStringDoesNotMatch() {
        XCTAssertFalse(AIProviderSupport.localModelSupportsTools(""))
    }

    func testLlama32DoesNotMatch() {
        // Regex covers 3.3 and above, not 3.2
        XCTAssertFalse(AIProviderSupport.localModelSupportsTools("llama-3.2-3b"))
    }
}
