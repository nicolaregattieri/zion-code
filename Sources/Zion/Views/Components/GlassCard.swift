import SwiftUI

struct GlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let spacing: CGFloat
    @ViewBuilder var content: Content

    init(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(12)
        .background(colorScheme == .dark ? .ultraThinMaterial : .regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.20) : Color.white.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.14 : 0.08), radius: 12, y: 4)
    }
}
