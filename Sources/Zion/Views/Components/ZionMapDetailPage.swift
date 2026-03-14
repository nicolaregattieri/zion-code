import SwiftUI

struct ZionMapDetailPage: View {
    let section: FeatureSection

    private var entries: [ZionMapEntry] {
        ZionMapContent.entries(for: section)
    }

    var body: some View {
        VStack(spacing: 0) {
            detailHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sectionHero
                    ForEach(entries) { entry in
                        entryCard(entry)
                    }
                }
                .padding(24)
            }
        }
        .toolbar(.hidden)
    }

    // MARK: - Header

    private var detailHeader: some View {
        HStack {
            Color.clear.frame(width: 60, height: 1)

            Spacer()

            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(section.color)
                Text(L10n(section.titleKey))
                    .font(DesignSystem.Typography.bodyLargeBold)
            }

            Spacer()

            // Balance the leading placeholder width
            Color.clear.frame(width: 60, height: 1)
        }
        .padding(20)
    }

    // MARK: - Section Hero

    private var sectionHero: some View {
        HStack(spacing: 16) {
            Image(systemName: section.icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(section.color)
                .frame(width: 48, height: 48)
                .background(section.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.containerCornerRadius))

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n(section.titleKey))
                    .font(.system(size: 18, weight: .bold))
                Text(L10n(section.subtitleKey))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Entry Card

    private func entryCard(_ entry: ZionMapEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title row with optional shortcut badge
            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                Text(L10n(entry.titleKey))
                    .font(DesignSystem.Typography.sectionTitle)

                if let shortcut = entry.shortcut {
                    Text(shortcut)
                        .font(DesignSystem.Typography.monoSmallMedium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(DesignSystem.Colors.glassSubtle)
                        .clipShape(Capsule())
                }

                Spacer()
            }

            // Description
            Text(L10n(entry.descriptionKey))
                .font(DesignSystem.Typography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Pro tips
            if !entry.tips.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(entry.tips, id: \.self) { tipKey in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "lightbulb.fill")
                                .font(DesignSystem.Typography.meta)
                                .foregroundStyle(DesignSystem.Colors.searchHighlight.opacity(0.8))
                                .padding(.top, 3)
                            Text(L10n(tipKey))
                                .font(DesignSystem.Typography.bodySmall)
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.glassSubtle)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous)
                .stroke(DesignSystem.Colors.glassBorderDark, lineWidth: 1)
        )
    }
}
