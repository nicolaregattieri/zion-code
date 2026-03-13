import SwiftUI

struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path: [FeatureSection] = []
    @State private var hoveredSection: FeatureSection?

    /// Ordered list of sections matching the original card layout
    private let sections: [FeatureSection] = FeatureSection.allCases

    private var balancedSectionColumns: ([FeatureSection], [FeatureSection]) {
        let sorted = sections.sorted { estimatedCardWeight(for: $0) > estimatedCardWeight(for: $1) }
        var left: [FeatureSection] = []
        var right: [FeatureSection] = []
        var leftWeight = 0
        var rightWeight = 0

        for section in sorted {
            let weight = estimatedCardWeight(for: section)
            if leftWeight <= rightWeight {
                left.append(section)
                leftWeight += weight
            } else {
                right.append(section)
                rightWeight += weight
            }
        }

        return (left, right)
    }

    /// Feature bullet keys per section (matching original HelpSheet content)
    private func featureKeys(for section: FeatureSection) -> [String] {
        switch section {
        case .tree:
            return ["help.tree.lanes", "help.tree.search", "help.tree.jumpbar",
                    "help.tree.pending", "help.tree.signature",
                    "help.tree.navigation", "help.tree.focus",
                    "help.commitStats", "help.avatars", "help.branchSearch"]
        case .code:
            return ["help.code.editor", "help.code.quickopen", "help.code.blame",
                    "help.code.themes", "help.code.unsaved", "help.code.newfile",
                    "help.code.saveas", "help.code.openineditor", "help.code.contextmenu",
                    "help.code.findreplace", "help.code.findinfiles",
                    "help.code.markdownpreview",
                    "help.code.navigation",
                    "help.code.tabsize", "help.code.columnruler",
                    "help.code.brackets", "help.code.indentguides", "help.code.repoconfig",
                    "help.code.filehistory", "help.code.openwith",
                    "help.code.format", "help.code.dotfiles"]
        case .terminal:
            return ["help.terminal.pty", "help.terminal.splits", "help.terminal.tabs",
                    "help.terminal.zoom", "help.terminal.persistence",
                    "help.terminal.transparency", "help.terminal.finderdrag",
                    "help.terminalSearch", "help.terminal.voiceInput"]
        case .clipboard:
            return ["help.clipboard.capture", "help.clipboard.paste",
                    "help.clipboard.drag", "help.clipboard.images",
                    "help.smartClipboard"]
        case .operations:
            return ["help.ops.commit", "help.ops.branch", "help.ops.stash",
                    "help.ops.rebase", "help.ops.hunk", "help.ops.tags",
                    "help.ops.forcepush",
                    "help.ops.init", "help.ops.recovery",
                    "help.stashBadge"]
        case .worktrees:
            return ["help.worktree.parallel", "help.worktree.quick", "help.worktree.terminal"]
        case .ai:
            return ["help.ai.commit", "help.ai.diff", "help.ai.pr", "help.ai.stash",
                    "help.ai.conflict", "help.ai.review", "help.ai.changelog",
                    "help.ai.search", "help.ai.branch", "help.ai.blame",
                    "help.ai.split", "help.ai.style", "help.ai.precommit",
                    "help.ai.slashcommands",
                    "help.aiSummary"]
        case .customization:
            return ["help.customization.languages", "help.customization.appearance",
                    "help.customization.confirmation",
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
        case .zionMode:
            return ["help.zionMode.toggle", "help.zionMode.shortcut", "help.zionMode.restore", "help.zionMode.theme"]
        case .mobileAccess:
            return ["help.mobile.pairing", "help.mobile.terminal", "help.mobile.quickActions",
                    "help.mobile.multiProject", "help.mobile.lanMode",
                    "help.mobile.cloudflare", "help.mobile.preventSleep"]
        case .bisect:
            return ["help.bisect.start", "help.bisect.banner", "help.bisect.visual",
                    "help.bisect.ai", "help.bisect.statusPill"]
        case .clone:
            return ["help.clone.sheet", "help.clone.welcome", "help.clone.protocol"]
        case .repoStats:
            return ["help.repoStats.card", "help.repoStats.languages"]
        case .remotes:
            return ["help.remotes.fetchPullPush", "help.remotes.divergence",
                    "help.remotes.manage", "help.remotes.testConnection"]
        case .submodules:
            return ["help.submodules.status", "help.submodules.init",
                    "help.submodules.update", "help.submodules.sync"]
        case .hosting:
            return ["help.hosting.autoDetect", "help.hosting.providers",
                    "help.hosting.createPR", "help.hosting.aiDescription"]
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

                    HStack(alignment: .top, spacing: 16) {
                        featureColumn(balancedSectionColumns.0)
                        featureColumn(balancedSectionColumns.1)
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
                .font(DesignSystem.Typography.sheetTitle)
                .foregroundStyle(.secondary)
            Text(L10n("Conheca o Zion"))
                .font(DesignSystem.Typography.sheetSectionTitle)
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
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n("help.hero.title"))
                .font(DesignSystem.Typography.sheetSectionTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(L10n("help.hero.subtitle"))
                .font(DesignSystem.Typography.cardBody)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                Button {
                    dismiss()
                    NotificationCenter.default.post(name: .showOnboarding, object: nil)
                } label: {
                    Label(L10n("help.openOnboarding"), systemImage: "sparkles.rectangle.stack")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Link(destination: URL(string: "https://zioncode.dev")!) {
                    Label(L10n("help.visitWebsite"), systemImage: "globe")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Feature Card

    private func featureCard(for section: FeatureSection) -> some View {
        let isHovered = hoveredSection == section
        let features = featureKeys(for: section).map { L10n($0) }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                Image(systemName: section.icon)
                    .font(DesignSystem.Typography.subtitle)
                    .foregroundStyle(section.color)
                    .frame(width: 28, height: 28)
                    .background(section.color.opacity(DesignSystem.Opacity.selectedSubtle))
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius))
                Text(L10n(section.titleKey))
                    .font(DesignSystem.Typography.sectionTitle)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(DesignSystem.Typography.labelSemibold)
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
                            .font(DesignSystem.Typography.bodySmall)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovered ? DesignSystem.Colors.glassHover : DesignSystem.Colors.glassSubtle)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous)
                .stroke(DesignSystem.Colors.glassBorderDark, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(DesignSystem.Motion.detail) {
                hoveredSection = hovering ? section : nil
            }
        }
    }

    private func featureColumn(_ sections: [FeatureSection]) -> some View {
        VStack(spacing: 16) {
            ForEach(sections) { section in
                Button {
                    path.append(section)
                } label: {
                    featureCard(for: section)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func estimatedCardWeight(for section: FeatureSection) -> Int {
        let featureCount = max(featureKeys(for: section).count, 1)
        return featureCount + 2
    }

    // MARK: - Shortcuts Highlight

    private var shortcutsHighlight: some View {
        HStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(DesignSystem.Typography.sheetBody)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n("help.shortcuts.title"))
                    .font(DesignSystem.Typography.bodyBold)
                Text(L10n("help.shortcuts.subtitle"))
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\u{2318}/")
                .font(DesignSystem.Typography.monoCardBody)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(DesignSystem.Colors.glassSubtle)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
        }
        .padding(14)
        .background(DesignSystem.Colors.glassSubtle)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous)
                .stroke(DesignSystem.Colors.glassBorderDark, lineWidth: 1)
        )
    }
}
