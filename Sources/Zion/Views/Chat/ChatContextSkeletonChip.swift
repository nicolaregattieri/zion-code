import SwiftUI

/// Phase 6 — shimmer placeholder rendered while the hybrid retrieval
/// is in flight. Only shows up after the
/// `Constants.RAG.autoSkeletonDelayMs` gate so cached / fast hits
/// never flash.
struct ChatContextSkeletonChip: View {

    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(DesignSystem.Typography.meta)
                .foregroundStyle(DesignSystem.Colors.ai.opacity(DesignSystem.Opacity.dim))
            Text(L10n("chat.context.loading"))
                .font(DesignSystem.Typography.monoLabel)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, DesignSystem.Spacing.compact)
        .padding(.vertical, 3)
        .background(DesignSystem.Colors.glassSubtle.opacity(0.6 + 0.4 * phase))
        .clipShape(Capsule())
        .overlay(
            Capsule().strokeBorder(DesignSystem.Colors.glassStroke.opacity(0.6), lineWidth: 1)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }
}
