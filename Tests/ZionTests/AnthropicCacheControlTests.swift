import XCTest
@testable import Zion

// Tests for provider prompt-caching: Anthropic cache_control + OpenAI message ordering.
// Each test uses an isolated UserDefaults suite to avoid polluting global state.
final class AnthropicCacheControlTests: XCTestCase {

    // Unique suite per test run to prevent cross-test contamination
    private var defaults: UserDefaults!
    private let suiteName = "com.zion.tests.cache.\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        // Reset to unset state so the default (true) is what we observe unless explicitly set
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        // Restore global cache.enabled to unset (true default) in case any test wrote it
        UserDefaults.standard.removeObject(forKey: "chat.cache.enabled")
        super.tearDown()
    }

    // MARK: - Helpers

    private func makePayload(system: String = "You are a helpful assistant.", user: String = "Hello") -> AIPromptPayload {
        AIPromptPayload(
            systemInstructions: system,
            taskInstructions: user,
            untrustedSections: [],
            suspiciousPatterns: []
        )
    }

    // MARK: - Test 1: system block has cache_control when caching enabled (default)

    func test_system_block_has_cache_control_when_enabled() {
        // Default: chat.cache.enabled not set → true
        UserDefaults.standard.removeObject(forKey: "chat.cache.enabled")

        let payload = makePayload(system: "System instructions here.")
        let body = AIClient.anthropicRequestBody(payload: payload, maxTokens: 1024, modelID: "claude-3-5-sonnet-20241022")

        // system field must be an array
        guard let systemArr = body["system"] as? [[String: Any]] else {
            XCTFail("Expected system to be [[String: Any]] when caching enabled, got: \(type(of: body["system"] as Any))")
            return
        }

        XCTAssertEqual(systemArr.count, 1, "Expected exactly one system block")

        let block = systemArr[0]
        XCTAssertEqual(block["type"] as? String, "text")
        XCTAssertEqual(block["text"] as? String, "System instructions here.")

        guard let cacheControl = block["cache_control"] as? [String: Any] else {
            XCTFail("Expected cache_control dict on system block")
            return
        }
        XCTAssertEqual(cacheControl["type"] as? String, "ephemeral")
    }

    // MARK: - Test 2: system block is plain String when caching disabled

    func test_system_block_plain_when_disabled() {
        UserDefaults.standard.set(false, forKey: "chat.cache.enabled")

        let payload = makePayload(system: "System instructions here.")
        let body = AIClient.anthropicRequestBody(payload: payload, maxTokens: 1024, modelID: "claude-3-5-sonnet-20241022")

        // system field must be a plain String, not an array
        guard let systemStr = body["system"] as? String else {
            XCTFail("Expected system to be String when caching disabled, got: \(type(of: body["system"] as Any))")
            return
        }
        XCTAssertEqual(systemStr, "System instructions here.")
    }

    // MARK: - Test 3: empty system prompt produces no cache_control marker

    func test_empty_system_no_cache_marker() {
        UserDefaults.standard.removeObject(forKey: "chat.cache.enabled")

        let payload = makePayload(system: "")
        let body = AIClient.anthropicRequestBody(payload: payload, maxTokens: 1024, modelID: "claude-3-5-sonnet-20241022")

        // When system is empty, anthropicSystemField returns "" (plain string, no array)
        let systemValue = body["system"]
        if let systemArr = systemValue as? [[String: Any]] {
            // If somehow an array, it should not contain cache_control
            for block in systemArr {
                XCTAssertNil(block["cache_control"], "Empty system should not emit cache_control")
            }
        } else if let systemStr = systemValue as? String {
            XCTAssertTrue(systemStr.isEmpty, "Empty system should return empty string")
        } else {
            // Absent / nil is also acceptable
        }
    }

    // MARK: - Test 4: OpenAI message array starts with system message

    func test_openai_message_array_starts_with_system() {
        let payload = makePayload(system: "Be helpful.", user: "What is Swift?")
        let body = AIClient.openAIRequestBody(payload: payload, maxTokens: 1024, modelID: "gpt-4o")

        guard let messages = body["messages"] as? [[String: Any]] else {
            XCTFail("Expected messages array")
            return
        }

        XCTAssertFalse(messages.isEmpty, "Messages should not be empty")
        let first = messages[0]
        XCTAssertEqual(first["role"] as? String, "system",
                       "First message must be system role for OpenAI prefix caching")
        XCTAssertEqual(first["content"] as? String, "Be helpful.")
    }

    // MARK: - Test 5: OpenAI message order preserved (system first, user second)

    func test_openai_message_order_preserved() {
        let payload = makePayload(system: "System prompt.", user: "User message.")
        let body = AIClient.openAIRequestBody(payload: payload, maxTokens: 512, modelID: "gpt-4o")

        guard let messages = body["messages"] as? [[String: Any]], messages.count >= 2 else {
            XCTFail("Expected at least 2 messages")
            return
        }

        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertEqual(messages[1]["role"] as? String, "user")
    }

    // MARK: - Test 6: anthropicSystemField helper — enabled with text

    func test_anthropicSystemField_enabled_with_text() {
        let result = AIClient.anthropicSystemField("My system prompt", cacheEnabled: true)
        guard let arr = result as? [[String: Any]], arr.count == 1 else {
            XCTFail("Expected single-element array when cacheEnabled=true")
            return
        }
        XCTAssertEqual(arr[0]["type"] as? String, "text")
        XCTAssertEqual(arr[0]["text"] as? String, "My system prompt")
        let cc = arr[0]["cache_control"] as? [String: Any]
        XCTAssertEqual(cc?["type"] as? String, "ephemeral")
    }

    // MARK: - Test 7: anthropicSystemField helper — disabled

    func test_anthropicSystemField_disabled() {
        let result = AIClient.anthropicSystemField("My system prompt", cacheEnabled: false)
        guard let str = result as? String else {
            XCTFail("Expected plain String when cacheEnabled=false")
            return
        }
        XCTAssertEqual(str, "My system prompt")
    }
}
