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
                        (L10n("Git Blame"), "⇧⌘B"),
                        (L10n("Barra lateral"), "⌘B"),
                        (L10n("Salvar"), "⌘S"),
                        (L10n("Terminal"), "⌘J"),
                        (L10n("Maximizar terminal"), "⇧⌘J"),
                    ])

                    shortcutSection(L10n("Terminal"), icon: "terminal", shortcuts: [
                        (L10n("Nova aba"), "⌘T"),
                        (L10n("Dividir verticalmente"), "⇧⌘D"),
                        (L10n("Dividir horizontalmente"), "⇧⌘E"),
                        (L10n("Fechar painel dividido"), "⇧⌘W"),
                        (L10n("Zoom in"), "⌃+"),
                        (L10n("Zoom out"), "⌃-"),
                    ])

                    shortcutSection(L10n("Grafo"), icon: "point.3.connected.trianglepath.dotted", shortcuts: [
                        (L10n("Buscar no grafo"), "⌘F"),
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
            HStack(spacing: 6) {
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
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }
}
