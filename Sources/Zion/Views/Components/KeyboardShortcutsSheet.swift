import SwiftUI

struct KeyboardShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var shortcutRegistry: ShortcutRegistry

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n("Atalhos de Teclado"))
                    .font(.title2.bold())
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DesignSystem.Typography.sheetTitle)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    ForEach(ShortcutSection.allCases, id: \.rawValue) { section in
                        let rows = rows(for: section)
                        if !rows.isEmpty {
                            shortcutSection(section.title, icon: section.icon, shortcuts: rows)
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            Text(
                L10n("Pressione") + " "
                + (shortcutRegistry.displayString(for: .showKeyboardShortcuts) ?? "⌥⌘K")
                + " "
                + L10n("para ver todos os atalhos")
            )
                .font(DesignSystem.Typography.label)
                .foregroundStyle(.tertiary)
                .padding(12)
        }
        .frame(width: 420, height: 520)
    }

    private func rows(for section: ShortcutSection) -> [(String, String)] {
        let registryRows = shortcutRegistry.definitions(in: section).compactMap { definition -> (String, String)? in
            guard let display = shortcutRegistry.displayString(for: definition.id) else { return nil }
            return (definition.title, display)
        }
        return registryRows + supplementalRows(for: section)
    }

    private func supplementalRows(for section: ShortcutSection) -> [(String, String)] {
        switch section {
        case .editor:
            return [
                (L10n("shortcuts.findInFilesClose"), "Esc"),
                (L10n("shortcuts.findInFilesNext"), "Enter"),
                (L10n("shortcuts.findNext"), "⌘G"),
                (L10n("shortcuts.cmdClickDefinition"), "⌘Click"),
            ]
        case .graph:
            return [
                (L10n("shortcuts.navigateCommits"), "↑↓"),
                (L10n("shortcuts.closeOrDeselect"), "Esc"),
            ]
        default:
            return []
        }
    }

    private func shortcutSection(_ title: String, icon: String, shortcuts: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                Image(systemName: icon)
                    .font(DesignSystem.Typography.bodySmallSemibold)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(DesignSystem.Typography.sectionTitle)
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
                .font(DesignSystem.Typography.body)
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
