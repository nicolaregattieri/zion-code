import SwiftUI

struct GlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let spacing: CGFloat
    let borderTint: Color?
    @ViewBuilder var content: Content

    init(spacing: CGFloat = 12, borderTint: Color? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.borderTint = borderTint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(DesignSystem.Spacing.cardPadding)
        .background(colorScheme == .dark ? .ultraThinMaterial : .regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius, style: .continuous)
                .stroke(
                    borderTint ?? (colorScheme == .dark ? DesignSystem.Colors.glassBorderDark : DesignSystem.Colors.glassBorderLight),
                    lineWidth: borderTint != nil ? 1.5 : 1
                )
        )
        .shadow(color: colorScheme == .dark ? DesignSystem.Colors.shadowDark : DesignSystem.Colors.shadowLight, radius: 12, y: 4)
    }
}

struct CardHeader: View {
    let title: String
    let icon: String
    let subtitle: String?
    let trailing: AnyView?

    init(_ title: String, icon: String, subtitle: String? = nil) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.trailing = nil
    }

    init(_ title: String, icon: String, subtitle: String? = nil, @ViewBuilder trailing: () -> some View) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(DesignSystem.IconSize.sectionHeader)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let trailing {
                trailing
            }
        }
    }
}
