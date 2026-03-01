import SwiftUI

struct KeyboardShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n("Atalhos de Teclado"))
                    .font(.title2.bold())
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    shortcutSection(L10n("Navegacao"), icon: "sidebar.left", shortcuts: [
                        (L10n("Codigo"), "⌘1"),
                        (L10n("Grafo"), "⌘2"),
                        (L10n("Operacoes"), "⌘3"),
                    ])

                    shortcutSection(L10n("Editor"), icon: "doc.text", shortcuts: [
                        (L10n("Quick Open"), "⌘P"),
                        (L10n("Barra lateral"), "⌘B"),
                        (L10n("Salvar"), "⌘S"),
                        (L10n("Novo Arquivo"), "⌘N"),
                        (L10n("Salvar Como..."), "⇧⌘S"),
                        (L10n("shortcuts.find"), "⌘F"),
                        (L10n("shortcuts.findAlias"), "⌃F"),
                        (L10n("shortcuts.findReplace"), "⌘H"),
                        (L10n("shortcuts.goToLine"), "⌘G"),
                        (L10n("shortcuts.selectNextOccurrence"), "⌘D"),
                        (L10n("shortcuts.goToDefinition"), "F12"),
                        (L10n("shortcuts.findReferences"), "⇧F12"),
                        (L10n("shortcuts.cmdClickDefinition"), "⌘Click"),
                        (L10n("Git Blame"), "⇧⌘B"),
                        (L10n("shortcuts.formatDocument"), "⇧⌥F"),
                    ])

                    shortcutSection(L10n("Terminal"), icon: "terminal", shortcuts: [
                        (L10n("Terminal"), "⌘J"),
                        (L10n("Maximizar terminal"), "⇧⌘J"),
                        (L10n("Nova aba"), "⌘T"),
                        (L10n("Dividir verticalmente"), "⇧⌘D"),
                        (L10n("Dividir horizontalmente"), "⇧⌘E"),
                        (L10n("Fechar painel dividido"), "⇧⌘W"),
                        (L10n("shortcuts.terminalSearch"), "⌘F"),
                        (L10n("Zoom in"), "⌃+"),
                        (L10n("Zoom out"), "⌃-"),
                    ])

                    shortcutSection(L10n("Grafo"), icon: "point.3.connected.trianglepath.dotted", shortcuts: [
                        (L10n("Buscar no grafo"), "⌘F"),
                        (L10n("shortcuts.navigateCommits"), "↑↓"),
                        (L10n("shortcuts.closeOrDeselect"), "Esc"),
                    ])

                    shortcutSection(L10n("shortcuts.general"), icon: "gearshape", shortcuts: [
                        (L10n("shortcuts.refreshRepository"), "⌘R"),
                        (L10n("shortcuts.codeReview"), "⇧⌘R"),
                        (L10n("zen.mode"), "⌃⌘J"),
                        (L10n("shortcuts.zionMode"), "⌃⌘Z"),
                        (L10n("Atalhos de Teclado"), "⌘/"),
                    ])
                }
                .padding(20)
            }

            Divider()

            Text(L10n("Pressione") + " ⌘? " + L10n("para ver todos os atalhos"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(12)
        }
        .frame(width: 420, height: 520)
    }

    private func shortcutSection(_ title: String, icon: String, shortcuts: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 13, weight: .bold))
            }

            VStack(spacing: 4) {
                ForEach(Array(shortcuts.enumerated()), id: \.offset) { _, shortcut in
                    shortcutRow(description: shortcut.0, keys: shortcut.1)
                }
            }
        }
        .padding(12)
        .background(DesignSystem.Colors.glassSubtle)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.containerCornerRadius, style: .continuous))
    }

    private func shortcutRow(description: String, keys: String) -> some View {
        HStack {
            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(keys)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(DesignSystem.Colors.glassSubtle)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
        }
    }
}
