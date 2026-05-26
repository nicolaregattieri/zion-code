import SwiftUI

/// Banner rendered in the composer's top slot when the active repo contains
/// CLAUDE.md / AGENTS.md / GEMINI.md / .cursorrules / .cursor/rules/* and
/// the user has not yet decided whether to import them into Zion Talks
/// context. Click Import → ChatContextBuilder.gitContextHeader prefixes
/// the imported content to the hidden context block on every turn for
/// this repo.
struct ProjectGuidanceImportBanner: View {

    let candidates: [ProjectGuidanceImporter.Candidate]
    let onImport: ([ProjectGuidanceImporter.Candidate]) -> Void
    let onDismiss: () -> Void

    @State private var selectedIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.compact) {
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                Image(systemName: "doc.badge.plus")
                    .foregroundStyle(DesignSystem.Colors.ai)
                Text(L10n("chat.projectGuidance.banner.title", "\(candidates.count)"))
                    .font(DesignSystem.Typography.bodySemibold)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n("chat.projectGuidance.banner.dismiss.help"))
            }

            Text(L10n("chat.projectGuidance.banner.subtitle"))
                .font(DesignSystem.Typography.label)
                .foregroundStyle(.secondary)

            // Per-candidate checkbox row. Defaults to all selected — user
            // typically wants the whole set.
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.micro) {
                ForEach(candidates) { candidate in
                    HStack(spacing: DesignSystem.Spacing.compact) {
                        Toggle(isOn: Binding(
                            get: { selectedIDs.contains(candidate.id) },
                            set: { isOn in
                                if isOn { selectedIDs.insert(candidate.id) }
                                else { selectedIDs.remove(candidate.id) }
                            }
                        )) {
                            HStack(spacing: 4) {
                                Text(candidate.label)
                                    .font(DesignSystem.Typography.monoSmall)
                                Text("· \(candidate.target)")
                                    .font(DesignSystem.Typography.label)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(formatBytes(candidate.sizeBytes))
                                    .font(DesignSystem.Typography.label)
                                    .foregroundStyle(.tertiary)
                                    .monospacedDigit()
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }

            HStack {
                Spacer()
                Button(L10n("chat.projectGuidance.banner.dismiss")) { onDismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button(L10n("chat.projectGuidance.banner.import")) {
                    let selected = candidates.filter { selectedIDs.contains($0.id) }
                    onImport(selected)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(selectedIDs.isEmpty)
            }
        }
        .padding(DesignSystem.Spacing.standard)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous)
                .fill(DesignSystem.Colors.ai.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous)
                .strokeBorder(DesignSystem.Colors.ai.opacity(0.4), lineWidth: 1)
        )
        .onAppear {
            // Pre-select everything so the common case (user just clicks Import)
            // is one click. The user can toggle off anything they want to skip.
            selectedIDs = Set(candidates.map(\.id))
        }
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
