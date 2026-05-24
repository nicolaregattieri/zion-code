import SwiftUI

/// Assistant-bubble variant rendered when `ChatMessage.helpCardPayload != nil`.
/// Displays collapsible sections for built-in commands, project/user skills,
/// @mention syntax, MCP tools, and keyboard shortcuts.
struct SlashHelpCard: View {
    let payload: HelpCardPayload
    @State private var expanded: Set<String> = ["builtin", "mentions", "shortcuts"]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.compact) {
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(DesignSystem.Colors.ai)
                Text(L10n("chat.slash.help.title"))
                    .font(DesignSystem.Typography.bodySemibold)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            }

            section(id: "builtin", title: L10n("chat.slash.help.section.builtin"), items: payload.builtInItems)

            if !payload.projectSkills.isEmpty {
                section(id: "project", title: L10n("chat.slash.help.section.project"), items: payload.projectSkills)
            }

            if !payload.userSkills.isEmpty {
                section(id: "user", title: L10n("chat.slash.help.section.user"), items: payload.userSkills)
            }

            section(id: "mentions", title: L10n("chat.slash.help.section.mentions"), items: payload.mentions)

            if !payload.mcpTools.isEmpty {
                section(id: "mcp", title: L10n("chat.slash.help.section.mcp"), items: payload.mcpTools)
            }

            section(id: "shortcuts", title: L10n("chat.slash.help.section.shortcuts"), items: payload.shortcuts)
        }
        .padding(DesignSystem.Spacing.cardPadding)
        .background(DesignSystem.Colors.glassSubtle)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius, style: .continuous)
                .strokeBorder(DesignSystem.Colors.glassStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func section(id: String, title: String, items: [HelpCardPayload.HelpCardItem]) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expanded.contains(id) },
                set: { open in
                    if open { expanded.insert(id) } else { expanded.remove(id) }
                }
            )
        ) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.micro) {
                ForEach(items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.iconLabelGap) {
                        Text(item.label)
                            .font(DesignSystem.Typography.monoLabelBold)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        Text(item.description)
                            .font(DesignSystem.Typography.label)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, DesignSystem.Spacing.micro)
        } label: {
            Text(title)
                .font(DesignSystem.Typography.bodySemibold)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
        }
    }
}
