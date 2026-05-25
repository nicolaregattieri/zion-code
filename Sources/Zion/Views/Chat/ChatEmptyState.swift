import SwiftUI

struct ChatEmptyState: View {
    let onPickPrompt: (String) -> Void

    private struct StarterCard: Identifiable {
        let id = UUID()
        let icon: String
        let titleKey: String
        let subtitleKey: String
        let prefill: String
    }

    private let cards: [StarterCard] = [
        StarterCard(
            icon: "doc.text.magnifyingglass",
            titleKey: "chat.emptyState.starter.browse.title",       // TODO(P14:T10)
            subtitleKey: "chat.emptyState.starter.browse.subtitle",  // TODO(P14:T10)
            prefill: "/repo_map "
        ),
        StarterCard(
            icon: "doc.text.below.ecg",
            titleKey: "chat.emptyState.starter.editFile.title",       // TODO(P14:T10)
            subtitleKey: "chat.emptyState.starter.editFile.subtitle", // TODO(P14:T10)
            prefill: "@file "
        ),
        StarterCard(
            icon: "terminal",
            titleKey: "chat.emptyState.starter.runTests.title",       // TODO(P14:T10)
            subtitleKey: "chat.emptyState.starter.runTests.subtitle", // TODO(P14:T10)
            prefill: "/bash swift test"
        ),
        StarterCard(
            icon: "questionmark.circle",
            titleKey: "chat.emptyState.starter.allCommands.title",       // TODO(P14:T10)
            subtitleKey: "chat.emptyState.starter.allCommands.subtitle", // TODO(P14:T10)
            prefill: "/help"
        ),
    ]

    /// True when no AI provider is connected — surfaces Smart Auto onboarding card.
    private var noProvidersConfigured: Bool {
        let providers: [AIProvider] = [.anthropic, .openai, .gemini, .local, .claudeCLI, .codexCLI]
        return !providers.contains(where: { AIProviderSupport.isConnected(provider: $0) })
    }

    var body: some View {
        VStack(alignment: .center, spacing: DesignSystem.Spacing.sectionGap) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(DesignSystem.Colors.ai)

            VStack(spacing: DesignSystem.Spacing.compact) {
                Text(L10n("chat.emptyState.hero.title"))
                    .font(DesignSystem.Typography.screenTitle)
                Text(L10n("chat.emptyState.hero.subtitle"))
                    .font(DesignSystem.Typography.subtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if noProvidersConfigured {
                smartAutoOnboardingCard
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: DesignSystem.Spacing.standard),
                    GridItem(.flexible(), spacing: DesignSystem.Spacing.standard)
                ],
                spacing: DesignSystem.Spacing.standard
            ) {
                ForEach(cards) { card in
                    Button {
                        onPickPrompt(card.prefill)
                    } label: {
                        starterCardView(card)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 600)
        }
        .padding(DesignSystem.Spacing.cardPadding * 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Smart Auto onboarding card — shown only when no provider is connected.
    /// Three CTAs: install Claude CLI (free subscription), install Ollama
    /// (free local), add API key.
    private var smartAutoOnboardingCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.compact) {
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                Image(systemName: "wand.and.stars")
                    .font(DesignSystem.Typography.subtitle)
                    .foregroundStyle(DesignSystem.Colors.ai)
                Text(L10n("chat.emptyState.smartAuto.title"))
                    .font(DesignSystem.Typography.bodySemibold)
            }
            Text(L10n("chat.emptyState.smartAuto.subtitle"))
                .font(DesignSystem.Typography.label)
                .foregroundStyle(.secondary)
            HStack(spacing: DesignSystem.Spacing.compact) {
                Link(destination: URL(string: "https://docs.anthropic.com/en/docs/claude-code")!) {
                    Label(L10n("chat.emptyState.smartAuto.installClaudeCLI"), systemImage: "terminal")
                        .font(DesignSystem.Typography.label)
                }
                .buttonStyle(.bordered)
                Link(destination: URL(string: "https://ollama.com/download")!) {
                    Label(L10n("chat.emptyState.smartAuto.installOllama"), systemImage: "cpu")
                        .font(DesignSystem.Typography.label)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(DesignSystem.Spacing.cardPadding)
        .frame(maxWidth: 600, alignment: .leading)
        .background(DesignSystem.Colors.glassSubtle)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius)
                .strokeBorder(DesignSystem.Colors.glassStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func starterCardView(_ card: StarterCard) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.compact) {
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                Image(systemName: card.icon)
                    .font(DesignSystem.Typography.subtitle)
                    .foregroundStyle(DesignSystem.Colors.ai)
                Text(L10n(card.titleKey))                       // TODO(P14:T10)
                    .font(DesignSystem.Typography.bodySemibold)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            }
            Text(L10n(card.subtitleKey))                        // TODO(P14:T10)
                .font(DesignSystem.Typography.label)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.cardPadding)
        .background(DesignSystem.Colors.glassSubtle)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius)
                .strokeBorder(DesignSystem.Colors.glassStroke, lineWidth: 1)
        )
    }
}
