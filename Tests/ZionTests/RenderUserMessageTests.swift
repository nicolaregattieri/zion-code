import XCTest
@testable import Zion

/// Phase 6.2 — pins the user-message rendering contract. The user's
/// actual prompt MUST NOT be wrapped in `<untrusted_repo_content>`
/// tags; doing so collides with the security-hardening rule and made
/// claude CLI refuse short follow-ups ("I'm sorry, but I can't assist
/// with that request"). Repo-content sections still get wrapped.
final class RenderUserMessageTests: XCTestCase {

    private func makePayload(userText: String, repoText: String? = nil) -> AIPromptPayload {
        var sections: [AIUntrustedPromptSection] = [
            AIUntrustedPromptSection(
                kind: "user_message",
                label: "User message",
                content: userText,
                maxLength: 4000
            )
        ]
        if let repo = repoText {
            sections.append(AIUntrustedPromptSection(
                kind: "file_content",
                label: "Foo.swift",
                content: repo,
                maxLength: 4000
            ))
        }
        return AIPromptPayload(
            systemInstructions: "",
            taskInstructions: "Be helpful.",
            untrustedSections: sections,
            suspiciousPatterns: []
        )
    }

    func test_userMessage_isNotWrappedInUntrustedTag() {
        let payload = makePayload(userText: "nao sei o que me sugere mostrar?")
        let rendered = AIClient.renderUserMessage(from: payload)
        XCTAssertFalse(
            rendered.contains("<untrusted_repo_content"),
            "User-message turns must not appear inside <untrusted_repo_content> — that wrapping made claude CLI refuse follow-ups"
        )
        XCTAssertTrue(rendered.contains("nao sei o que me sugere mostrar?"))
    }

    func test_repoContent_stillWrapped_andLabeledUntrusted() {
        let payload = makePayload(
            userText: "where is L10n loaded?",
            repoText: "let value = bundle.localizedString(forKey: key)"
        )
        let rendered = AIClient.renderUserMessage(from: payload)
        XCTAssertTrue(rendered.contains("<untrusted_repo_content"),
                      "Repo content must keep the untrusted wrapper")
        XCTAssertTrue(rendered.contains("Untrusted repository content follows"))
        XCTAssertTrue(rendered.contains("where is L10n loaded?"),
                      "User message must still appear, just outside the wrapper")
    }

    func test_userMessage_appendsAtEnd() {
        let payload = makePayload(
            userText: "PROMPT_END",
            repoText: "// repo middle"
        )
        let rendered = AIClient.renderUserMessage(from: payload)
        // The user prompt is the LAST thing the model sees, after the
        // repo data block. Otherwise the wrap-up of trust-flagged data
        // would visually drown the actual question.
        let userIdx = rendered.range(of: "PROMPT_END")?.lowerBound
        let repoIdx = rendered.range(of: "// repo middle")?.lowerBound
        XCTAssertNotNil(userIdx)
        XCTAssertNotNil(repoIdx)
        if let u = userIdx, let r = repoIdx {
            XCTAssertGreaterThan(u, r, "User message should come after the repo content section")
        }
    }
}
