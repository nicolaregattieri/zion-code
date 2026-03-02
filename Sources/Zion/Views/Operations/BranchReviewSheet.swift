import SwiftUI

struct BranchReviewSheet: View {
    @Bindable var model: RepositoryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()

            branchPickers

            if model.isBranchReviewLoading {
                loadingView
            } else if !model.branchReviewFindings.isEmpty {
                ScrollView {
                    ReviewFindingsView(
                        findings: model.branchReviewFindings,
                        tintColor: DesignSystem.Colors.ai,
                        onOpenFile: { file, snippet in
                            model.openFileInEditor(relativePath: file, highlightQuery: snippet)
                        }
                    )
                }
            } else {
                emptyState
            }

            Spacer(minLength: 0)

            HStack {
                Button(L10n("Fechar")) { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.escape, modifiers: [])

                if !model.branchReviewFindings.isEmpty {
                    Button {
                        dismiss()
                        model.startCodeReview(source: model.branchReviewSource, target: model.branchReviewTarget)
                    } label: {
                        Label(L10n("branch.review.fullReview"), systemImage: "rectangle.expand.vertical")
                    }
                    .buttonStyle(.bordered)
                    .help(L10n("branch.review.fullReview.hint"))
                }

                Spacer()
                Button {
                    model.reviewBranch(source: model.branchReviewSource, target: model.branchReviewTarget)
                } label: {
                    if model.isBranchReviewLoading {
                        ProgressView().controlSize(.small).frame(width: 12, height: 12)
                    } else {
                        Label(L10n("branch.review.button"), systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.ai)
                .disabled(
                    model.branchReviewSource.isEmpty
                        || model.branchReviewTarget.isEmpty
                        || model.branchReviewSource == model.branchReviewTarget
                        || model.isBranchReviewLoading
                )
            }
        }
        .padding(24)
        .frame(width: 600, height: 420)
        .onAppear { model.ensureBranchReviewSelections() }
    }

    private var header: some View {
        HStack(spacing: DesignSystem.Spacing.toolbarItemGap) {
            Image(systemName: "arrow.triangle.branch")
                .font(.title3)
                .foregroundStyle(DesignSystem.Colors.ai)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n("branch.review.title"))
                    .font(.title3.bold())
                Text(L10n("branch.review.subtitle"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var branchPickers: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n("branch.review.target"))
                    .font(DesignSystem.Typography.label).foregroundStyle(.secondary)
                Picker("", selection: $model.branchReviewTarget) {
                    Text(L10n("Selecionar...")).tag("")
                    if !model.localBranchOptions.isEmpty {
                        Section(L10n("branch.group.local")) {
                            ForEach(model.localBranchOptions, id: \.self) { branch in
                                Text(branch).tag(branch)
                            }
                        }
                    }
                    if !model.remoteBranchOptions.isEmpty {
                        Section(L10n("branch.group.remote")) {
                            ForEach(model.remoteBranchOptions, id: \.self) { branch in
                                Text(branch).tag(branch)
                            }
                        }
                    }
                    if model.localBranchOptions.isEmpty && model.remoteBranchOptions.isEmpty {
                        ForEach(model.branches, id: \.self) { branch in
                            Text(branch).tag(branch)
                        }
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Image(systemName: "arrow.left")
                .font(DesignSystem.Typography.label)
                .foregroundStyle(.secondary)
                .padding(.top, 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n("branch.review.source"))
                    .font(DesignSystem.Typography.label).foregroundStyle(.secondary)
                Picker("", selection: $model.branchReviewSource) {
                    Text(L10n("Selecionar...")).tag("")
                    if !model.localBranchOptions.isEmpty {
                        Section(L10n("branch.group.local")) {
                            ForEach(model.localBranchOptions, id: \.self) { branch in
                                Text(branch).tag(branch)
                            }
                        }
                    }
                    if !model.remoteBranchOptions.isEmpty {
                        Section(L10n("branch.group.remote")) {
                            ForEach(model.remoteBranchOptions, id: \.self) { branch in
                                Text(branch).tag(branch)
                            }
                        }
                    }
                    if model.localBranchOptions.isEmpty && model.remoteBranchOptions.isEmpty {
                        ForEach(model.branches, id: \.self) { branch in
                            Text(branch).tag(branch)
                        }
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(L10n("branch.review.loading"))
                .font(DesignSystem.Typography.label)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(L10n("branch.review.empty"))
                .font(DesignSystem.Typography.label)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}
