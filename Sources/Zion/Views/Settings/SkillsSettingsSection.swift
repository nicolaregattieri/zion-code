import SwiftUI

// MARK: - SkillsSettingsSection

struct SkillsSettingsSection: View {
    // Phase 6.3 — use the process-wide shared index (audit P1) so the
    // Settings panel reflects skills ChatService injects + paste-to-
    // install scaffolds. Without this the panel showed a separate
    // local list that drifted on every reload.
    @ObservedObject private var index = SkillIndex.shared
    @State private var showNewSkillSheet = false

    var body: some View {
        Section(L10n("chat.skills.section.title")) { // TODO(P14:T10)
            if index.skills.isEmpty {
                Text(L10n("chat.skills.empty")) // TODO(P14:T10)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(index.skills) { skill in
                    HStack(spacing: DesignSystem.Spacing.standard) {
                        Image(systemName: skill.scope == .project ? "folder" : "house")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("/" + skill.id)
                                .font(DesignSystem.Typography.monoLabelBold)
                            Text(skill.description)
                                .font(DesignSystem.Typography.label)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Text(skill.scope == .project
                             ? L10n("chat.skills.scope.project") // TODO(P14:T10)
                             : L10n("chat.skills.scope.user"))   // TODO(P14:T10)
                            .font(DesignSystem.Typography.metaSemibold)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                }
            }
            Button(L10n("chat.skills.newSkill")) { // TODO(P14:T10)
                showNewSkillSheet = true
            }
        }
        .task { await index.reload() }
        .sheet(isPresented: $showNewSkillSheet) {
            NewSkillSheet(onSave: { name, description, scope in
                _ = try? index.scaffold(name: name, description: description, scope: scope)
                Task { await index.reload() }
                showNewSkillSheet = false
            })
        }
    }
}

// MARK: - NewSkillSheet

private struct NewSkillSheet: View {
    let onSave: (String, String, SkillScope) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var scopeRaw = SkillScope.user.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.cardPadding) {
            Text(L10n("chat.skills.newSkill.title")) // TODO(P14:T10)
                .font(DesignSystem.Typography.cardTitle)
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.standard) {
                TextField(L10n("chat.skills.newSkill.name"), text: $name)
                    .textFieldStyle(.roundedBorder)

                // Skill description IS the skill body — system prompt the LLM
                // sees when the slash command fires. Single-line TextField was
                // misleading: users typed one sentence and lost the instruction
                // surface. Multi-line editor with a visible label + min height
                // signals "this is real content, not a tagline".
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.micro) {
                    Text(L10n("chat.skills.newSkill.description"))
                        .font(DesignSystem.Typography.labelMedium)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $description)
                        .font(DesignSystem.Typography.body)
                        .frame(minHeight: 160, maxHeight: 320)
                        .padding(DesignSystem.Spacing.micro)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(DesignSystem.Colors.glassSubtle)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(DesignSystem.Colors.glassStroke, lineWidth: 1)
                        )
                }

                Picker(L10n("chat.skills.newSkill.scope"), selection: $scopeRaw) {
                    Text(L10n("chat.skills.scope.user")).tag(SkillScope.user.rawValue)
                    Text(L10n("chat.skills.scope.project")).tag(SkillScope.project.rawValue)
                }
                .pickerStyle(.segmented)
            }
            HStack {
                Button(L10n("chat.skills.newSkill.cancel"), role: .cancel) { dismiss() } // TODO(P14:T10)
                Spacer()
                Button(L10n("chat.skills.newSkill.save")) { // TODO(P14:T10)
                    let scope = SkillScope(rawValue: scopeRaw) ?? .user
                    onSave(name, description, scope)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }
        .padding(DesignSystem.Spacing.cardPadding * 2)
        .frame(minWidth: 520, minHeight: 460)
    }
}
