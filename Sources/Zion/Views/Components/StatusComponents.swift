import SwiftUI

struct StatPill: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.containerCornerRadius, style: .continuous)
                .fill(DesignSystem.Colors.glassElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.containerCornerRadius, style: .continuous)
                .stroke(DesignSystem.Colors.glassStroke, lineWidth: 1)
        )
    }
}

struct StatusChip: View {
    let title: String
    let value: String
    let tint: Color
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous)
                .fill(tint.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous)
                .stroke(tint.opacity(0.2), lineWidth: 1)
        )
    }
}
