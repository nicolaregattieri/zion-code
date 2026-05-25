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
    private var previewModelID: String? {
        if let txt = livePreviewText, !txt.trimmingCharacters(in: .whitespaces).isEmpty,
           let tier = previewTier, let provider = chat.resolvedProvider {
            return SmartAutoTierTable.default.modelID(provider: provider, tier: tier)
        }
        return chat.resolvedModelID
    }

    private static func syncClassify(_ text: String) -> SmartAutoTier {
        HeuristicTriageClassifier.classifySync(text)
    }

    var body: some View {
        if isAuto, let resolved = chat.resolvedProvider {
            HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                Image(systemName: "arrow.triangle.branch")
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(DesignSystem.Colors.ai)
                Text(L10n("chat.auto.resolvedChip", resolved.label))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
                if let model = previewModelID, !model.isEmpty {
                    Text("·")
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.tertiary)
                    Text(model)
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.primary)
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
