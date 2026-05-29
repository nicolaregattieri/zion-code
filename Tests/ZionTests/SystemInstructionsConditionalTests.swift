import XCTest
@testable import Zion

/// Phase 6.3 — system-instructions security rules are only injected when
/// the payload actually carries untrusted repo content. Pure
/// conversation turns (only `user_message` section) get a friendlier
/// system prompt so local Coder models (Qwen / MLX variants) stop
/// refusing innocuous follow-ups with "I'm sorry, but I can't assist
/// with that request" (user report screenshot #60).
final class SystemInstructionsConditionalTests: XCTestCase {

    func test_systemInstructions_skipsSecurityRules_whenNoRepoContent() {
        let s = AIClient.makeSystemInstructions(for: "Chat", hasRepoContent: false)
        XCTAssertTrue(s.contains("You are Zion's AI assistant."))
        XCTAssertFalse(s.contains("Security rules"))
        XCTAssertFalse(s.contains("untrusted"))
    }

    func test_systemInstructions_includesSecurityRules_whenRepoContent() {
        let s = AIClient.makeSystemInstructions(for: "Chat", hasRepoContent: true)
        XCTAssertTrue(s.contains("Security rules"))
        XCTAssertTrue(s.contains("untrusted"))
    }

    func test_payload_userMessageOnly_skipsSecurityRules() {
        let payload = AIClient.makePromptPayload(
            task: "Chat",
            taskInstructions: "Be helpful.",
            untrustedSections: [
                AIUntrustedPromptSection(
                    kind: "user_message",
                    label: "User",
                    content: "consigo adicionar um mcp aqui?",
                    maxLength: 4000
                )
            ]
        )
        XCTAssertFalse(payload.systemInstructions.contains("Security rules"))
    }

    func test_payload_withRepoContent_includesSecurityRules() {
        let payload = AIClient.makePromptPayload(
            task: "Chat",
            taskInstructions: "Be helpful.",
            untrustedSections: [
                AIUntrustedPromptSection(
                    kind: "user_message",
                    label: "User",
                    content: "explain Foo",
                    maxLength: 4000
                ),
                AIUntrustedPromptSection(
                    kind: "file_content",
                    label: "Foo.swift",
                    content: "let x = 1",
                    maxLength: 4000
                ),
            ]
        )
        XCTAssertTrue(payload.systemInstructions.contains("Security rules"))
    }
}
