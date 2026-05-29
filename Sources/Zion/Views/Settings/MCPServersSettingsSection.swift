import SwiftUI

// MARK: - MCPServersSettingsSection

struct MCPServersSettingsSection: View {
    @State private var store = MCPRegistryStore()
    @State private var showEditor: Bool = false
    @State private var editingConfig: MCPServerConfig? = nil

    var body: some View {
        // MARK: - TODO(P14:T10): L10n
        Section(L10n("chat.mcp.section.title")) {
            ForEach(store.servers) { server in
                row(server)
            }
            HStack {
                Button(L10n("chat.mcp.newServer")) {
                    editingConfig = nil
                    showEditor = true
                }
                Spacer()
                Link(L10n("chat.mcp.findMore"),
                     destination: URL(string: "https://registry.modelcontextprotocol.io")!)
                    .font(DesignSystem.Typography.label)
            }
        }
        .task {
            try? await store.load()
            // Phase 6.3 — keep the list reactive to paste-to-install
            // events and external edits to ~/.zion/mcp.json. Without
            // startWatching the user had to leave + reopen Settings to
            // see new servers (audit P1).
            await store.startWatching()
        }
        .onDisappear {
            Task { await store.stopWatching() }
        }
        .sheet(isPresented: $showEditor) {
            MCPServerEditorSheet(initial: editingConfig) { config in
                Task {
                    if editingConfig == nil {
                        _ = try? await store.addServer(config)
                    } else {
                        try? await store.removeServer(id: editingConfig!.id)
                        _ = try? await store.addServer(config)
                    }
                    showEditor = false
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ server: MCPServerConfig) -> some View {
        HStack(spacing: DesignSystem.Spacing.standard) {
            statusDot(for: server)
            VStack(alignment: .leading, spacing: 2) {
                Text(server.id)
                    .font(DesignSystem.Typography.bodySemibold)
                Text(server.command + " " + server.args.joined(separator: " "))
                    .font(DesignSystem.Typography.monoLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Menu {
                Button(L10n("chat.mcp.menu.editConfig")) {
                    editingConfig = server
                    showEditor = true
                }
                Button(role: .destructive) {
                    Task { try? await store.removeServer(id: server.id) }
                } label: {
                    Text(L10n("chat.mcp.menu.remove"))
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func statusDot(for server: MCPServerConfig) -> some View {
        let color: Color = server.disabled ? .gray : .green
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
}
