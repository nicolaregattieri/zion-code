import XCTest
@testable import Zion

/// Phase 6.3 — system-prompt MUST surface `create_skill` and
/// `install_mcp_server` so the model knows it can act on natural-
/// language requests ("save this session as a skill", "add the
/// filesystem MCP") instead of telling the user to edit JSON / open
/// Settings.
final class ExtensibilityDirectiveTests: XCTestCase {

    func test_taskInstructions_anthropicProvider_mentionsCreateSkill() {
        let s = chatInstructions(for: .anthropic)
        XCTAssertTrue(s.contains("create_skill"))
        XCTAssertTrue(s.contains("install_mcp_server"))
        XCTAssertTrue(s.contains("save this as a skill"))
    }

    func test_taskInstructions_localProvider_mentionsExtensibility() {
        let s = chatInstructions(for: .local)
        XCTAssertTrue(s.contains("Extending Zion"))
        XCTAssertTrue(s.contains("`.zion/skills/`") || s.contains("~/.zion/skills/"))
    }

    func test_taskInstructions_claudeCLI_alsoCarriesDirective() {
        let s = chatInstructions(for: .claudeCLI)
        XCTAssertTrue(s.contains("create_skill"))
    }

    func test_directive_warnsAgainstSettingsPaneAdvice() {
        let s = chatInstructions(for: .anthropic)
        XCTAssertTrue(s.contains("Do NOT ask the user to edit JSON files"))
    }

    // MARK: - Helper

    /// Wraps the private `ChatService.taskInstructions(for:)` via the
    /// same path send() uses (`makePromptPayload`). We don't have a
    /// public test seam, so build a payload and read systemInstructions
    /// + taskInstructions (which renderUserMessage appends).
    private func chatInstructions(for provider: AIProvider) -> String {
        let payload = AIClient.makePromptPayload(
            task: "Chat",
            taskInstructions: chatTaskInstructions(for: provider),
            untrustedSections: []
        )
        return payload.taskInstructions
    }

    /// Calls the same module-private logic via the public render path.
    /// Workaround: build a ChatService briefly to call `makePayload`
    /// would require the actor harness; instead reach through the
    /// `Self.taskInstructions(for:)` static via a reflection helper if
    /// one is exposed. For now we read the string directly via the
    /// public API: `ChatService` exposes `branchAwarenessAppendixForTesting`,
    /// add a sibling test seam.
    private func chatTaskInstructions(for provider: AIProvider) -> String {
        return ChatService.taskInstructionsForTesting(provider: provider)
    }
}
