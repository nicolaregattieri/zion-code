import SwiftUI

struct TagDetailSheet: View {
    @Bindable var model: RepositoryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isCreating: Bool = false
    @State private var selectedRemote: String = "origin"

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "tag")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.info)
                Text(L10n("tag.detail.title"))
                    .font(.headline)
                Spacer()
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Tag name
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n("Tags"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                        TextField("v1.0.0", text: $model.tagInput)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Tag type
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n("tag.detail.type"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                        Picker("", selection: $model.tagType) {
                            ForEach(TagType.allCases) { type in
                                Text(type.label).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Message (for annotated/signed)
                    if model.tagType != .lightweight {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n("tag.detail.message"))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextEditor(text: $model.tagMessage)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(minHeight: 80)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius)
                                        .stroke(DesignSystem.Colors.glassBorderDark)
                                )
                        }
                    }

                    // Push toggle
                    Toggle(isOn: $model.tagPushAfterCreate) {
                        Text(L10n("tag.detail.pushAfterCreate"))
                            .font(.system(size: 12))
                    }
                    .toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.actionPrimary))
                    .tint(DesignSystem.Colors.actionPrimary)

                    // Remote picker (if push enabled)
                    if model.tagPushAfterCreate {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n("tag.detail.targetRemote"))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $selectedRemote) {
                                ForEach(model.remotes) { remote in
                                    Text(remote.name).tag(remote.name)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 200)
                        }
                    }
                }
                .padding(16)
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button(L10n("Cancelar")) { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button {
                    createTag()
                } label: {
                    if isCreating {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(L10n("Criar"), systemImage: "tag")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(DesignSystem.Colors.actionPrimary)
                .disabled(model.tagInput.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
            }
            .padding(16)
        }
        .frame(width: 480, height: model.tagType == .lightweight ? 340 : 440)
        .onAppear {
            if let first = model.remotes.first {
                selectedRemote = first.name
            }
        }
    }

    private func createTag() {
        isCreating = true
        let tagName = model.tagInput.trimmingCharacters(in: .whitespaces)
        let message = model.tagMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldPush = model.tagPushAfterCreate
        let remote = selectedRemote
        let type = model.tagType

        model.createTag(named: tagName, at: "HEAD", message: message, type: type)

        // Push after create if toggled
        if shouldPush {
            // Delay slightly to allow tag creation to complete
            Task {
                try? await Task.sleep(nanoseconds: Constants.Timing.repositorySwitchPollInterval)
                model.pushTag(named: tagName, to: remote)
            }
        }

        isCreating = false
        dismiss()
    }
}
