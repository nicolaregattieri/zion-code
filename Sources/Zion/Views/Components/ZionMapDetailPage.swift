import SwiftUI

struct ZionMapDetailPage: View {
    let section: FeatureSection
    @Environment(\.dismiss) private var dismiss

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
            Button {
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text(L10n("Voltar"))
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(section.color)
                Text(L10n(section.titleKey))
                    .font(.system(size: 14, weight: .bold))
            }

            Spacer()

            // Balance the back button width
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
            HStack(spacing: 8) {
                Text(L10n(entry.titleKey))
                    .font(.system(size: 13, weight: .bold))

                if let shortcut = entry.shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(DesignSystem.Colors.glassSubtle)
                        .clipShape(Capsule())
                }

                Spacer()
            }

            // Description
            Text(L10n(entry.descriptionKey))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Pro tips
            if !entry.tips.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(entry.tips, id: \.self) { tipKey in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.yellow.opacity(0.8))
                                .padding(.top, 3)
                            Text(L10n(tipKey))
                                .font(.system(size: 11))
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
