import SwiftUI

/// Phase 5 RAG settings panel. Surfaces the kill-switch toggle, the
/// "Reindex" button, and a footer with chunk count + last index
/// timestamp. UserDefaults keys mirror `Constants.Feature.*` shape.
struct RAGSettingsSection: View {

    @AppStorage("rag.hybridEnabled") private var hybridEnabled: Bool = true
    @AppStorage("rag.qodoEnabled") private var qodoEnabled: Bool = false
    @AppStorage("rag.chunkCount") private var chunkCount: Int = 0
    @AppStorage("rag.lastIndexed") private var lastIndexedRaw: Double = 0

    /// Closure plumbed by the parent view that knows the active
    /// repoURL. When nil, the Reindex button is hidden.
    let onReindex: (() -> Void)?

    @State private var reindexing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.standard) {
            Text(L10n("rag.settings.title"))
                .font(DesignSystem.Typography.sheetTitle)

            Toggle(L10n("rag.settings.hybridToggle"), isOn: $hybridEnabled)
                .tint(DesignSystem.Colors.ai)

            Toggle(L10n("rag.backend.qodo"), isOn: $qodoEnabled)
                .tint(DesignSystem.Colors.ai)

            if let onReindex {
                HStack {
                    Button(L10n("rag.settings.reindex")) {
                        reindexing = true
                        onReindex()
                    }
                    .buttonStyle(.bordered)
                    .disabled(reindexing)
                    if reindexing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Spacer()
                }
            }

            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                Text(String(format: L10n("rag.settings.chunkCount"), chunkCount))
                    .font(DesignSystem.Typography.monoLabel)
                    .foregroundStyle(.secondary)
                if lastIndexedRaw > 0 {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(L10n("rag.settings.lastIndexed") + " " + Self.formatTimestamp(lastIndexedRaw))
                        .font(DesignSystem.Typography.monoLabel)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(DesignSystem.Spacing.cardPadding)
        .background(DesignSystem.Colors.glassSubtle)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous))
    }

    private static func formatTimestamp(_ raw: Double) -> String {
        let date = Date(timeIntervalSince1970: raw)
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
