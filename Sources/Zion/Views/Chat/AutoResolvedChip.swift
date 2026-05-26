import SwiftUI

// MARK: - AutoResolvedChip
// Shown in the composer area only when the selected provider is .auto AND the
// orchestrator has resolved a concrete provider for the latest send.
// Tells the user "Auto → Claude" so the routing is transparent.

struct AutoResolvedChip: View {

    @Bindable var chat: ChatService
    /// Live composer text — when bound, the chip previews the tier the
    /// classifier WILL pick before the user sends. Lets the user see "easy/medium/hard"
    /// shift as they type. Nil = behave as the legacy after-send chip.
    let livePreviewText: String?
    @AppStorage(UserDefaultsKeys.AI.provider) private var providerRaw: String = AIProvider.none.rawValue

    init(chat: ChatService, livePreviewText: String? = nil) {
        self.chat = chat
        self.livePreviewText = livePreviewText
    }

    private var isAuto: Bool {
        (AIProvider(rawValue: providerRaw) ?? .none) == .auto
    }

    /// Live tier derived from composer text (sync, sub-ms heuristic).
    /// Falls back to chat.resolvedTier when composer is empty / no preview.
    private var previewTier: SmartAutoTier? {
        if let txt = livePreviewText, !txt.trimmingCharacters(in: .whitespaces).isEmpty {
            // Heuristic is pure + async — call via Task-detached unsafe trick is
            // overkill; the actor isolation is trivial. Use static sync helper.
            return Self.syncClassify(txt)
        }
        return chat.resolvedTier
    }

    /// Live model id derived from preview tier + currently-resolved provider.
    /// Falls back to chat.resolvedModelID when no live text.
    /// For `.local` the SmartAutoTierTable returns nil (the user picks the
    /// model in Settings → Local), so we read the actual configured model name
    /// from `AIClient.loadLocalConfig()` to keep the chip honest — without
    /// this the user sees the generic "Local / OpenAI-compatible" label with
    /// no hint of which model is actually answering.
    private var previewModelID: String? {
        if let txt = livePreviewText, !txt.trimmingCharacters(in: .whitespaces).isEmpty,
           let tier = previewTier, let provider = chat.resolvedProvider {
            if let m = SmartAutoTierTable.default.modelID(provider: provider, tier: tier), !m.isEmpty {
                return m
            }
            return Self.fallbackModelID(for: provider)
        }
        if let cached = chat.resolvedModelID, !cached.isEmpty {
            return cached
        }
        if let provider = chat.resolvedProvider {
            return Self.fallbackModelID(for: provider)
        }
        return nil
    }

    /// Provider-specific fallback when the tier table does not pin a model.
    /// Today only `.local` needs this; once `customEndpoint` lands, add its
    /// own loader here too so the chip can show e.g. the OpenRouter model id.
    private static func fallbackModelID(for provider: AIProvider) -> String? {
        switch provider {
        case .local:
            let name = AIClient.loadLocalConfig()?.modelName ?? ""
            return name.isEmpty ? nil : name
        default:
            return nil
        }
    }

    private static func syncClassify(_ text: String) -> SmartAutoTier {
        HeuristicTriageClassifier.classifySync(text)
    }

    /// HuggingFace-style IDs are `org/model-tag-quant`. The org prefix is
    /// noise for a status pill — drop it and keep the tail. Full id stays in
    /// the `.help()` tooltip on hover.
    /// Short provider label tuned for the status pill. The full provider
    /// label is descriptive ("Local / OpenAI-compatible") which is helpful in
    /// Settings but redundant here — the model name already disambiguates
    /// local vs remote OpenAI-compatible.
    private static func shortLabel(for provider: AIProvider) -> String {
        switch provider {
        case .local: return L10n("chat.auto.providerShort.local")
        default: return provider.label
        }
    }

    private static func shortenModelID(_ id: String) -> String {
        guard let slash = id.lastIndex(of: "/") else { return id }
        return String(id[id.index(after: slash)...])
    }

    var body: some View {
        if isAuto, let resolved = chat.resolvedProvider {
            HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                Image(systemName: "arrow.triangle.branch")
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(DesignSystem.Colors.ai)
                Text(L10n("chat.auto.resolvedChip", Self.shortLabel(for: resolved)))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
                if let model = previewModelID, !model.isEmpty {
                    Text("·")
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.tertiary)
                    Text(Self.shortenModelID(model))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(model)
                }
                if let tier = previewTier {
                    Text("·")
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.tertiary)
                    Text(tier.label)
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(tierColor(for: tier))
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.compact)
            .padding(.vertical, DesignSystem.Spacing.micro)
            .background(Capsule().fill(DesignSystem.Colors.glassSubtle))
        }
    }

    private func tierColor(for tier: SmartAutoTier) -> Color {
        switch tier {
        case .easy:   return .green
        case .medium: return .orange
        case .hard:   return .red
        }
    }
}
