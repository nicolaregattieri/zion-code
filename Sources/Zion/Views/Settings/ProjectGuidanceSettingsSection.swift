import SwiftUI

/// Settings list of repos with active project-guidance imports
/// (CLAUDE.md / AGENTS.md / GEMINI.md / .cursorrules) along with a per-row
/// "Clear" button so the user can revoke an import + re-show the banner on
/// next visit to that repo.
struct ProjectGuidanceSettingsSection: View {

    @State private var rows: [ProjectGuidanceImporter.ImportedRepo] = []

    var body: some View {
        Section {
            if rows.isEmpty {
                Text(L10n("settings.ai.projectGuidance.empty"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: DesignSystem.Spacing.standard) {
                        Image(systemName: "doc.badge.plus")
                            .foregroundStyle(DesignSystem.Colors.ai)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.repoURL.lastPathComponent)
                                .font(DesignSystem.Typography.bodySemibold)
                            Text(homeAliasedPath(row.repoURL.path))
                                .font(DesignSystem.Typography.label)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(row.repoURL.path)
                            Text(row.sources.joined(separator: " · "))
                                .font(DesignSystem.Typography.label)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Text(formatBytes(row.sizeBytes))
                            .font(DesignSystem.Typography.label)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                        Button(L10n("settings.ai.projectGuidance.clear")) {
                            ProjectGuidanceImporter.shared.reset(for: row.repoURL)
                            reload()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.red)
                    }
                }
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n("settings.ai.projectGuidance.title"))
                Text(L10n("settings.ai.projectGuidance.subtitle"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
        .task { reload() }
    }

    private func reload() {
        rows = ProjectGuidanceImporter.shared.allImported()
    }

    /// Replaces the user's home prefix with `~` so middle-truncation in
    /// narrow Settings layouts keeps the meaningful tail of the path
    /// (folder name) instead of dropping it.
    private func homeAliasedPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes >= 1024 * 1024 {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
        if bytes >= 1024 {
            return String(format: "%.0f KB", Double(bytes) / 1024)
        }
        return "\(bytes) B"
    }
}
