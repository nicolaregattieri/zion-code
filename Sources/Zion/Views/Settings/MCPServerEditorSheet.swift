import SwiftUI

// MARK: - MCPServerEditorSheet

struct MCPServerEditorSheet: View {
    let initial: MCPServerConfig?
    let onSave: (MCPServerConfig) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var id: String = ""
    @State private var command: String = ""
    @State private var argsText: String = ""
    @State private var disabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.cardPadding) {
            // MARK: - TODO(P14:T10): L10n
            Text(initial == nil ? L10n("chat.mcp.editor.titleNew") : L10n("chat.mcp.editor.titleEdit"))
                .font(DesignSystem.Typography.cardTitle)

            // Presets
            HStack(spacing: DesignSystem.Spacing.standard) {
                Button(L10n("chat.mcp.preset.filesystem")) { loadPreset(.filesystem) }
                Button(L10n("chat.mcp.preset.git")) { loadPreset(.git) }
                Button(L10n("chat.mcp.preset.github")) { loadPreset(.github) }
            }

            Form {
                TextField(L10n("chat.mcp.editor.id"), text: $id)
                TextField(L10n("chat.mcp.editor.command"), text: $command)
                TextField(L10n("chat.mcp.editor.args"), text: $argsText)
                Toggle(L10n("chat.mcp.editor.disabled"), isOn: $disabled)
            }

            HStack {
                Button(L10n("chat.mcp.editor.cancel"), role: .cancel) { dismiss() }
                Spacer()
                Button(L10n("chat.mcp.editor.save")) {
                    let config = MCPServerConfig(
                        id: id,
                        command: command,
                        args: argsText.split(separator: " ").map(String.init),
                        env: [:],
                        transport: "stdio",
                        disabled: disabled,
                        autoApprove: []
                    )
                    onSave(config)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(id.isEmpty || command.isEmpty)
            }
        }
        .padding(DesignSystem.Spacing.cardPadding * 2)
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            if let initial {
                id = initial.id
                command = initial.command
                argsText = initial.args.joined(separator: " ")
                disabled = initial.disabled
            }
        }
    }

    // MARK: - Presets

    private enum Preset { case filesystem, git, github }

    private func loadPreset(_ p: Preset) {
        switch p {
        case .filesystem:
            id = "filesystem"
            command = "npx"
            argsText = "@modelcontextprotocol/server-filesystem /tmp"
        case .git:
            id = "git"
            command = "uvx"
            argsText = "mcp-server-git --repository ."
        case .github:
            id = "github"
            command = "npx"
            argsText = "@modelcontextprotocol/server-github"
        }
    }
}
