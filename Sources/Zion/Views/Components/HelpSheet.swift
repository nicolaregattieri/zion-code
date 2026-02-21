import SwiftUI

struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path: [FeatureSection] = []
    @State private var hoveredSection: FeatureSection?

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    /// Ordered list of sections matching the original card layout
    private let sections: [FeatureSection] = FeatureSection.allCases

    /// Feature bullet keys per section (matching original HelpSheet content)
    private func featureKeys(for section: FeatureSection) -> [String] {
        switch section {
        case .tree:
            return ["help.tree.lanes", "help.tree.search", "help.tree.jumpbar",
                    "help.tree.pending", "help.tree.signature"]
        case .code:
            return ["help.code.editor", "help.code.quickopen", "help.code.blame",
                    "help.code.themes", "help.code.unsaved", "help.code.newfile",
                    "help.code.saveas", "help.code.openineditor", "help.code.contextmenu",
                    "help.code.findreplace", "help.code.tabsize", "help.code.columnruler",
                    "help.code.brackets", "help.code.indentguides", "help.code.repoconfig"]
        case .terminal:
            return ["help.terminal.pty", "help.terminal.splits", "help.terminal.tabs",
                    "help.terminal.zoom", "help.terminal.persistence"]
        case .clipboard:
            return ["help.clipboard.capture", "help.clipboard.paste",
                    "help.clipboard.drag", "help.clipboard.images"]
        case .operations:
            return ["help.ops.commit", "help.ops.branch", "help.ops.stash",
                    "help.ops.rebase", "help.ops.hunk"]
        case .worktrees:
            return ["help.worktree.parallel", "help.worktree.quick", "help.worktree.terminal"]
        case .ai:
            return ["help.ai.commit", "help.ai.diff", "help.ai.pr", "help.ai.stash",
                    "help.ai.conflict", "help.ai.review", "help.ai.changelog",
                    "help.ai.search", "help.ai.branch", "help.ai.blame",
                    "help.ai.split", "help.ai.style"]
        case .customization:
            return ["help.customization.languages", "help.customization.appearance",
                    "help.customization.editor", "help.customization.confirmation",
                    "help.customization.reflog"]
        case .diagnostics:
            return ["help.diagnostics.export", "help.diagnostics.copy", "help.diagnostics.sanitize"]
        case .conflicts:
            return ["help.conflicts.resolve", "help.conflicts.choose", "help.conflicts.continue"]
        case .settings:
            return L10n("help.settings.features").split(separator: "|").map(String.init)
        case .diffExplanation:
            return L10n("help.diffExplanation.features").split(separator: "|").map(String.init)
        case .codeReview:
            return L10n("help.codeReview.features").split(separator: "|").map(String.init)
        case .prInbox:
            return L10n("help.prInbox.features").split(separator: "|").map(String.init)
        case .autoUpdates:
            return ["help.updates.check", "help.updates.auto", "help.updates.delta"]
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            discoverGrid
                .frame(width: 720, height: 680)
                .navigationDestination(for: FeatureSection.self) { section in
                    ZionMapDetailPage(section: section)
                        .frame(width: 720, height: 680)
                }
        }
        .toolbar(.hidden)
    }

    // MARK: - Discover Grid (root page)

    private var discoverGrid: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    heroSection

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(sections) { section in
                            Button {
                                path.append(section)
                            } label: {
                                featureCard(for: section)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    shortcutsHighlight
                }
                .padding(24)
            }
        }
    }

    // MARK: - Header

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

    // MARK: - Hero

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

    // MARK: - Feature Card

    private func featureCard(for section: FeatureSection) -> some View {
        let isHovered = hoveredSection == section
        let features = featureKeys(for: section).map { L10n($0) }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(section.color)
                    .frame(width: 28, height: 28)
                    .background(section.color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                Text(L10n(section.titleKey))
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .opacity(isHovered ? 1 : 0.5)
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(features.enumerated()), id: \.offset) { _, text in
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(section.color.opacity(0.5))
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
        .background(isHovered ? DesignSystem.Colors.glassHover : DesignSystem.Colors.glassSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DesignSystem.Colors.glassBorderDark, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredSection = hovering ? section : nil
            }
        }
    }

    // MARK: - Shortcuts Highlight

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
            Text("\u{2318}?")
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
