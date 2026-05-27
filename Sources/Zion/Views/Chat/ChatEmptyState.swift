import SwiftUI

struct ChatEmptyState: View {
    /// Active repo URL — kept so the pre-flight chip row (and any future
    /// quick-action chips like "Run tests") can surface stack-aware defaults.
    let repoURL: URL?
    /// Closure kept for source-compatibility with existing call sites.
    /// The starter cards that previously consumed it have been replaced by
    /// `ChatPreflightChipRow`; the prefill path is no longer wired here.
    let onPickPrompt: (String) -> Void

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

            ChatPreflightChipRow()
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
}
