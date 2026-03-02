import SwiftUI

struct GlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.zionModeEnabled) private var zionMode
    let spacing: CGFloat
    let borderTint: Color?
    let expanding: Bool
    @ViewBuilder var content: Content

    init(spacing: CGFloat = 12, borderTint: Color? = nil, expanding: Bool = false, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.borderTint = borderTint
        self.expanding = expanding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
            if expanding { Spacer(minLength: 0) }
        }
        .frame(maxHeight: expanding ? .infinity : nil, alignment: .topLeading)
        .padding(DesignSystem.Spacing.cardPadding)
        .background(colorScheme == .dark ? .ultraThinMaterial : .regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius, style: .continuous)
                .stroke(
                    borderTint ?? (zionMode ? DesignSystem.ZionMode.glowBorder : (colorScheme == .dark ? DesignSystem.Colors.glassBorderDark : DesignSystem.Colors.glassBorderLight)),
                    lineWidth: borderTint != nil ? 1.5 : 1
                )
        )
        .shadow(
            color: zionMode ? DesignSystem.ZionMode.glowShadow : (colorScheme == .dark ? DesignSystem.Colors.shadowDark : DesignSystem.Colors.shadowLight),
            radius: 12,
            y: zionMode ? 2 : 4
        )
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
        HStack(spacing: DesignSystem.Spacing.iconTextGap) {
            Image(systemName: icon)
                .font(DesignSystem.IconSize.sectionHeader)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(DesignSystem.Typography.sheetTitle)
                if let subtitle {
                    Text(subtitle).font(DesignSystem.Typography.label).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let trailing {
                trailing
            }
        }
    }
}
