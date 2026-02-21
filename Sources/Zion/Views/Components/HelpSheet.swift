import SwiftUI

struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    heroSection
                    LazyVGrid(columns: columns, spacing: 16) {
                        featureCard(
                            icon: "point.3.connected.trianglepath.dotted",
                            color: .purple,
                            title: L10n("Zion Tree"),
                            features: [
                                L10n("help.tree.lanes"),
                                L10n("help.tree.search"),
                                L10n("help.tree.jumpbar"),
                                L10n("help.tree.pending"),
                                L10n("help.tree.signature"),
                            ]
                        )

                        featureCard(
                            icon: "terminal.fill",
                            color: .green,
                            title: L10n("Zion Code"),
                            features: [
                                L10n("help.code.editor"),
                                L10n("help.code.quickopen"),
                                L10n("help.code.blame"),
                                L10n("help.code.themes"),
                                L10n("help.code.unsaved"),
                            ]
                        )

                        featureCard(
                            icon: "rectangle.split.1x2",
                            color: .blue,
                            title: L10n("Terminal"),
                            features: [
                                L10n("help.terminal.pty"),
                                L10n("help.terminal.splits"),
                                L10n("help.terminal.tabs"),
                                L10n("help.terminal.zoom"),
                                L10n("help.terminal.persistence"),
                            ]
                        )

                        featureCard(
                            icon: "clipboard",
                            color: .orange,
                            title: L10n("Clipboard Inteligente"),
                            features: [
                                L10n("help.clipboard.capture"),
                                L10n("help.clipboard.paste"),
                                L10n("help.clipboard.drag"),
                                L10n("help.clipboard.images"),
                            ]
                        )

                        featureCard(
                            icon: "gearshape.2.fill",
                            color: .indigo,
                            title: L10n("Centro de Operacoes"),
                            features: [
                                L10n("help.ops.commit"),
                                L10n("help.ops.branch"),
                                L10n("help.ops.stash"),
                                L10n("help.ops.rebase"),
                                L10n("help.ops.hunk"),
                            ]
                        )

                        featureCard(
                            icon: "arrow.triangle.branch",
                            color: .teal,
                            title: L10n("Worktrees"),
                            features: [
                                L10n("help.worktree.parallel"),
                                L10n("help.worktree.quick"),
                                L10n("help.worktree.terminal"),
                            ]
                        )

                        featureCard(
                            icon: "sparkles",
                            color: .pink,
                            title: L10n("Assistente IA"),
                            features: [
                                L10n("help.ai.commit"),
                                L10n("help.ai.diff"),
                                L10n("help.ai.pr"),
                                L10n("help.ai.stash"),
                                L10n("help.ai.conflict"),
                                L10n("help.ai.review"),
                                L10n("help.ai.changelog"),
                                L10n("help.ai.search"),
                                L10n("help.ai.branch"),
                                L10n("help.ai.blame"),
                                L10n("help.ai.split"),
                                L10n("help.ai.style"),
                            ]
                        )

                        featureCard(
                            icon: "globe",
                            color: .cyan,
                            title: L10n("help.customization.title"),
                            features: [
                                L10n("help.customization.languages"),
                                L10n("help.customization.appearance"),
                                L10n("help.customization.editor"),
                                L10n("help.customization.confirmation"),
                                L10n("help.customization.reflog"),
                            ]
                        )

                        featureCard(
                            icon: "doc.text.magnifyingglass",
                            color: .gray,
                            title: L10n("help.diagnostics.title"),
                            features: [
                                L10n("help.diagnostics.export"),
                                L10n("help.diagnostics.copy"),
                                L10n("help.diagnostics.sanitize"),
                            ]
                        )

                        featureCard(
                            icon: "exclamationmark.triangle.fill",
                            color: .orange,
                            title: L10n("help.conflicts.title"),
                            features: [
                                L10n("help.conflicts.resolve"),
                                L10n("help.conflicts.choose"),
                                L10n("help.conflicts.continue"),
                            ]
                        )
                    }

                    shortcutsHighlight
                }
                .padding(24)
            }
        }
        .frame(width: 680, height: 640)
    }

    private var header: some View {
        HStack {
            Image(systemName: "questionmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(L10n("Conheca o Zion"))
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
    }

    private var heroSection: some View {
        VStack(spacing: 8) {
            Text(L10n("help.hero.title"))
                .font(.system(size: 18, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(L10n("help.hero.subtitle"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func featureCard(icon: String, color: Color, title: String, features: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                Text(title)
                    .font(.system(size: 13, weight: .bold))
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(features.enumerated()), id: \.offset) { _, text in
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(color.opacity(0.5))
                            .frame(width: 4, height: 4)
                            .padding(.top, 5)
                        Text(text)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.glassSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DesignSystem.Colors.glassBorderDark, lineWidth: 1)
        )
    }

    private var shortcutsHighlight: some View {
        HStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n("help.shortcuts.title"))
                    .font(.system(size: 12, weight: .bold))
                Text(L10n("help.shortcuts.subtitle"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("⌘?")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(DesignSystem.Colors.glassSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(14)
        .background(DesignSystem.Colors.glassSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DesignSystem.Colors.glassBorderDark, lineWidth: 1)
        )
    }
}
