import SwiftUI

struct PullUpstreamPickerSheet: View {
    @Bindable var model: RepositoryViewModel
    @Environment(\.dismiss) private var dismiss

    private var remoteBranchesForSelectedRemote: [String] {
        let prefix = model.pullUpstreamPickerRemote + "/"
        return model.branchInfos
            .filter { $0.isRemote && $0.name.hasPrefix(prefix) }
            .map { String($0.name.dropFirst(prefix.count)) }
            .filter { !$0.isEmpty && $0 != "HEAD" }
            .sorted()
    }

    private var canConfirm: Bool {
        !model.pullUpstreamPickerRemote.clean.isEmpty
            && !model.pullUpstreamPickerBranch.clean.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "arrow.down.to.line")
                    .font(DesignSystem.Typography.sheetTitle)
                    .foregroundStyle(DesignSystem.Colors.info)
                Text(L10n("pull.upstream.title"))
                    .font(DesignSystem.Typography.sheetTitle)
                Spacer()
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n("pull.upstream.subtitle"))
                        .font(DesignSystem.Typography.bodySmall)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n("pull.upstream.remote"))
                            .font(DesignSystem.Typography.bodySmallBold)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $model.pullUpstreamPickerRemote) {
                            ForEach(model.remotes) { remote in
                                Text(remote.name).tag(remote.name)
                            }
                            if model.remotes.isEmpty {
                                Text("origin").tag("origin")
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n("pull.upstream.branch"))
                            .font(DesignSystem.Typography.bodySmallBold)
                            .foregroundStyle(.secondary)

                        let suggestions = remoteBranchesForSelectedRemote
                        if suggestions.isEmpty {
                            TextField(L10n("pull.upstream.branchPlaceholder"), text: $model.pullUpstreamPickerBranch)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            Picker("", selection: $model.pullUpstreamPickerBranch) {
                                if !suggestions.contains(model.pullUpstreamPickerBranch),
                                   !model.pullUpstreamPickerBranch.clean.isEmpty {
                                    Text(model.pullUpstreamPickerBranch).tag(model.pullUpstreamPickerBranch)
                                }
                                ForEach(suggestions, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                    }

                    Toggle(isOn: $model.pullUpstreamPickerSetUpstream) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n("pull.upstream.setUpstream"))
                                .font(DesignSystem.Typography.body)
                            Text(L10n("pull.upstream.setUpstreamHint"))
                                .font(DesignSystem.Typography.bodySmall)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.actionPrimary))
                    .tint(DesignSystem.Colors.actionPrimary)
                }
                .padding(16)
            }

            Divider()

            HStack {
                Spacer()
                Button(L10n("Cancelar")) {
                    model.isPullUpstreamPickerVisible = false
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)

                Button {
                    model.confirmPullWithUpstream()
                    dismiss()
                } label: {
                    Label(L10n("pull.upstream.pull"), systemImage: "arrow.down.to.line")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(DesignSystem.Colors.actionPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(!canConfirm)
            }
            .padding(16)
        }
        .frame(width: 460, height: 360)
    }
}
