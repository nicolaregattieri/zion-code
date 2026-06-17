import SwiftUI

struct KeyboardShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var shortcutRegistry: ShortcutRegistry

    @State private var editingAction: ShortcutActionID?
    @State private var pendingBinding: ShortcutBinding?
    @State private var conflictingActions: [ShortcutActionID] = []
    @State private var searchQuery: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchField
            Divider()
            scrollContent
            Divider()
            footer
        }
        .frame(width: 480, height: 580)
    }

    private var header: some View {
        HStack {
            Text(L10n("Atalhos de Teclado"))
                .font(.title2.bold())
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(DesignSystem.Typography.sheetTitle)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(20)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
            TextField(L10n("shortcuts.searchPlaceholder"), text: $searchQuery)
                .textFieldStyle(.plain)
                .font(DesignSystem.Typography.body)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                ForEach(ShortcutSection.allCases, id: \.rawValue) { section in
                    let definitions = filteredDefinitions(for: section)
                    let supplemental = filteredSupplementalRows(for: section)
                    if !definitions.isEmpty || !supplemental.isEmpty {
                        shortcutSection(section, definitions: definitions, supplementalRows: supplemental)
                    }
                }
            }
            .padding(20)
        }
    }

    private var footer: some View {
        HStack {
            if !shortcutRegistry.overrides.isEmpty {
                Button(L10n("shortcuts.resetAll")) {
                    shortcutRegistry.resetAllOverrides()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Spacer()
            Text(
                L10n("Pressione") + " "
                + (shortcutRegistry.displayString(for: .showKeyboardShortcuts) ?? "⌥⌘K")
                + " "
                + L10n("para ver todos os atalhos")
            )
            .font(DesignSystem.Typography.label)
            .foregroundStyle(.tertiary)
        }
        .padding(12)
    }

    // MARK: - Filtering

    private func filteredDefinitions(for section: ShortcutSection) -> [ShortcutDefinition] {
        let all = shortcutRegistry.definitions(in: section)
        guard !searchQuery.isEmpty else { return all }
        let query = searchQuery.lowercased()
        return all.filter { $0.title.lowercased().contains(query) }
    }

    private func filteredSupplementalRows(for section: ShortcutSection) -> [(String, String)] {
        let all = supplementalRows(for: section)
        guard !searchQuery.isEmpty else { return all }
        let query = searchQuery.lowercased()
        return all.filter { $0.0.lowercased().contains(query) }
    }

    private func supplementalRows(for section: ShortcutSection) -> [(String, String)] {
        switch section {
        case .editor:
            return [
                (L10n("shortcuts.findInFilesClose"), "Esc"),
                (L10n("shortcuts.findInFilesNext"), "Enter"),
                (L10n("shortcuts.findNext"), "⌃G"),
                (L10n("shortcuts.cmdClickDefinition"), "⌘Click"),
                (L10n("shortcuts.markdownReader"), "⇧⌘M"),
                (L10n("shortcuts.markdownReaderSidebar"), "⌘O"),
            ]
        case .graph:
            return [
                (L10n("shortcuts.navigateCommits"), "↑↓"),
                (L10n("shortcuts.closeOrDeselect"), "Esc"),
            ]
        default:
            return []
        }
    }

    // MARK: - Section View

    private func shortcutSection(_ section: ShortcutSection, definitions: [ShortcutDefinition], supplementalRows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                Image(systemName: section.icon)
                    .font(DesignSystem.Typography.bodySmallSemibold)
                    .foregroundStyle(.secondary)
                Text(section.title)
                    .font(DesignSystem.Typography.sectionTitle)
            }

            VStack(spacing: 4) {
                ForEach(definitions) { definition in
                    editableShortcutRow(definition: definition)
                }
                ForEach(Array(supplementalRows.enumerated()), id: \.offset) { _, row in
                    staticShortcutRow(description: row.0, keys: row.1)
                }
            }
        }
        .padding(12)
        .background(DesignSystem.Colors.glassSubtle)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.containerCornerRadius, style: .continuous))
    }

    // MARK: - Editable Row

    private func editableShortcutRow(definition: ShortcutDefinition) -> some View {
        let isEditing = editingAction == definition.id
        let isOverridden = shortcutRegistry.overrides[definition.id] != nil
        let binding = shortcutRegistry.binding(for: definition.id)

        return VStack(spacing: 2) {
            HStack {
                HStack(spacing: 4) {
                    if isOverridden {
                        Circle()
                            .fill(DesignSystem.Colors.brandPrimary)
                            .frame(width: 6, height: 6)
                    }
                    Text(definition.title)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(isEditing ? .primary : .secondary)
                }

                Spacer()

                if isEditing {
                    ShortcutRecorderView(
                        currentBinding: binding,
                        onRecord: { newBinding in
                            handleRecordedBinding(newBinding, for: definition)
                        },
                        onCancel: {
                            editingAction = nil
                            pendingBinding = nil
                            conflictingActions = []
                        }
                    )
                } else {
                    HStack(spacing: 4) {
                        if let display = binding?.displayString {
                            Text(display)
                                .font(DesignSystem.Typography.monoBody)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(DesignSystem.Colors.glassSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
                        }

                        if isOverridden {
                            Button {
                                shortcutRegistry.setOverride(nil, for: definition.id)
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(DesignSystem.Typography.label)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(L10n("shortcuts.reset"))
                        }
                    }
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius)
                    .fill(isEditing ? DesignSystem.Colors.brandPrimary.opacity(0.08) : .clear)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering && !isEditing {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onTapGesture {
                if !isEditing {
                    editingAction = definition.id
                    pendingBinding = nil
                    conflictingActions = []
                }
            }

            if isEditing, !conflictingActions.isEmpty, let pending = pendingBinding {
                conflictResolutionBar(pending: pending, definition: definition)
            }
        }
    }

    // MARK: - Conflict Resolution

    private func conflictResolutionBar(pending: ShortcutBinding, definition: ShortcutDefinition) -> some View {
        let conflictNames = conflictingActions.compactMap { shortcutRegistry.definition(for: $0)?.title }
        let conflictText = String(format: L10n("shortcuts.recorder.conflictsWith"), conflictNames.joined(separator: ", "))

        return HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.warning)
            Text(conflictText)
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.warning)
            Spacer()
            Button(L10n("shortcuts.replace")) {
                for conflict in conflictingActions {
                    shortcutRegistry.setOverride(nil, for: conflict)
                }
                shortcutRegistry.setOverride(pending, for: definition.id)
                editingAction = nil
                pendingBinding = nil
                conflictingActions = []
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.warning)
            .controlSize(.mini)

            Button(L10n("Cancelar")) {
                editingAction = nil
                pendingBinding = nil
                conflictingActions = []
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.top, 4)
    }

    // MARK: - Static Row

    private func staticShortcutRow(description: String, keys: String) -> some View {
        HStack {
            Text(description)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(.secondary)
            Spacer()
            Text(keys)
                .font(DesignSystem.Typography.monoBody)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(DesignSystem.Colors.glassSubtle)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
        }
    }

    // MARK: - Logic

    private func handleRecordedBinding(_ binding: ShortcutBinding, for definition: ShortcutDefinition) {
        let conflicts = shortcutRegistry.conflicts(for: definition.id, binding: binding)
        if conflicts.isEmpty {
            shortcutRegistry.setOverride(binding, for: definition.id)
            editingAction = nil
            pendingBinding = nil
            conflictingActions = []
        } else {
            pendingBinding = binding
            conflictingActions = conflicts
        }
    }
}
