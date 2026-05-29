import Foundation

/// Phase 6.3 — handles paste-to-install events from the composer.
/// Mirrors Cursor / Claude Desktop behaviour: when the user pastes
/// MCP-server JSON or a SKILL.md block into the chat input, the app
/// installs it and surfaces a short transient banner instead of
/// dropping the raw text into the composer.
@MainActor
extension ChatService {

    func handlePasteAutoInstall(_ payload: PasteAutoInstall) async {
        switch payload {
        case .mcpJSON(let raw):
            await installPastedMCP(raw: raw)
        case .skillMarkdown(let name, let description, let body, let triggers):
            await installPastedSkill(
                name: name,
                description: description,
                body: body,
                triggers: triggers
            )
        }
    }

    private func installPastedMCP(raw: String) async {
        let result = (try? await MCPConfigBuilder.dispatchInstallMCPServer(args: ["json": raw])) ?? "[error: dispatch failed]"
        // Partial-success handling (audit P1): one paste can install N
        // servers, some succeeding, some failing. dispatch returns
        // "Installed: a\nFailed: b (reason)". Prefer the failure key
        // so the user notices the half-success.
        let installed = result.range(of: "Installed:") != nil
        let failed = result.range(of: "Failed:") != nil
        let key: String
        if installed && !failed { key = "chat.paste.mcp.installed" }
        else if installed && failed { key = "chat.paste.mcp.failed" }
        else { key = "chat.paste.mcp.failed" }
        showTransientNotice(L10n(key, result.replacingOccurrences(of: "\n", with: " · ")))
    }

    private func installPastedSkill(
        name: String,
        description: String,
        body: String,
        triggers: [String]
    ) async {
        var args: [String: Any] = [
            "name": name,
            "description": description,
            "body": body
        ]
        if !triggers.isEmpty { args["triggers"] = triggers }
        let result = (try? await MCPConfigBuilder.dispatchCreateSkill(args: args)) ?? "[error: dispatch failed]"
        if result.hasPrefix("Created") {
            // Audit P1: reload SkillIndex so the slash picker + Settings
            // panel see the new entry immediately. Without this the
            // user has to wait for the next periodic reload.
            await SkillIndex.shared.reload()
            showTransientNotice(L10n("chat.paste.skill.installed", name))
        } else {
            showTransientNotice(L10n("chat.paste.skill.failed", result))
        }
    }
}
