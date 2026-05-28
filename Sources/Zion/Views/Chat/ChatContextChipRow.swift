import SwiftUI

/// Phase 6 — auto-context chip row rendered above the composer between
/// `ChatPreflightChipRow` (policy) and `AttachmentChipRow` (user
/// attachments). Collapsed by default into a single summary pill via
/// `@AppStorage("chat.context.collapsed")` so the composer top slot
/// never becomes a wall of pills. Click toggles expanded state.
struct ChatContextChipRow: View {

    /// Hits the parent service has already retrieved + budget-filtered.
    let hits: [RAGHit]
    /// True while a hybrid query is in flight; the row renders a single
    /// shimmer skeleton instead of the chip list.
    let isLoading: Bool
    /// Caller injects this so dismissing a chip drops it from the
    /// upcoming message's injected context.
    let onRemove: (RAGHit) -> Void

    @AppStorage("chat.context.collapsed") private var collapsed: Bool = true

    var body: some View {
        if isLoading {
            HStack(spacing: 6) {
                ChatContextSkeletonChip()
                Spacer(minLength: 0)
            }
            .transition(.opacity)
        } else if hits.isEmpty {
            EmptyView()
        } else if collapsed {
            collapsedSummary
        } else {
            expandedRow
        }
    }

    private var collapsedSummary: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { collapsed = false }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(DesignSystem.Colors.ai)
                Text(String(format: L10n("chat.context.summary"), hits.count, estimatedTokens))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, DesignSystem.Spacing.compact)
            .padding(.vertical, 3)
            .background(DesignSystem.Colors.glassSubtle)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(DesignSystem.Colors.glassStroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private var expandedRow: some View {
        let visible = Array(hits.prefix(Constants.RAG.autoMaxVisibleChips))
        let overflow = max(0, hits.count - visible.count)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { collapsed = true }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 18, minHeight: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n("chat.context.title"))

                ForEach(visible, id: \.chunk.contentSHA) { hit in
                    ChatContextChip(hit: hit) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            onRemove(hit)
                        }
                    }
                }
                if overflow > 0 {
                    Text(String(format: L10n("chat.context.more"), overflow))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, DesignSystem.Spacing.compact)
                        .padding(.vertical, 3)
                        .background(DesignSystem.Colors.glassSubtle)
                        .clipShape(Capsule())
                }
            }
        }
        .transition(.opacity)
    }

    private var estimatedTokens: Int {
        hits.reduce(0) { sum, hit in
            sum + ChatContextAutoInjector.estimateChunkTokens(hit.chunk)
        }
    }
}
