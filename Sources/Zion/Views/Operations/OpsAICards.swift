import SwiftUI
import AppKit

// MARK: - Changelog Card

struct OpsChangelogCard: View {
    @Bindable var model: RepositoryViewModel

    var body: some View {
        GlassCard(spacing: 10, expanding: true) {
            CardHeader(L10n("Changelog"), icon: "sparkles", subtitle: L10n("Gerar notas de release com IA"))
            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                TextField(L10n("De (tag/hash)"), text: $model.changelogFromRef)
                    .textFieldStyle(.roundedBorder)
                TextField(L10n("Ate (tag/hash)"), text: $model.changelogToRef)
                    .textFieldStyle(.roundedBorder)
                Button {
                    model.generateChangelog()
                } label: {
                    if model.isGeneratingAIMessage {
                        ProgressView().controlSize(.small).frame(width: 12, height: 12)
                    } else {
                        Label(L10n("Gerar"), systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.ai)
                .disabled(model.isGeneratingAIMessage)
                .help(L10n("Gerar notas de release com IA"))
            }
        }
        .sheet(isPresented: $model.isChangelogSheetVisible) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(L10n("Changelog")).font(.title3.bold())
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.aiChangelog, forType: .string)
                    } label: {
                        Label(L10n("Copiar"), systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button(L10n("Fechar")) { model.isChangelogSheetVisible = false }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.escape, modifiers: [])
                }
                ScrollView {
                    Text(model.aiChangelog)
                        .font(DesignSystem.Typography.monoBody)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(DesignSystem.Spacing.screenEdge)
            .frame(width: 550, height: 450)
        }
    }
}

// MARK: - Code Review Card

struct OpsCodeReviewCard: View {
    @Bindable var model: RepositoryViewModel

    var body: some View {
        GlassCard(spacing: 10, expanding: true) {
            CardHeader(L10n("codereview.card.title"), icon: "magnifyingglass", subtitle: L10n("codereview.card.subtitle"))

            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
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

            if !model.branchReviewSource.isEmpty
                && !model.branchReviewTarget.isEmpty
                && model.branchReviewSource == model.branchReviewTarget {
                Text(L10n("codereview.sameBranch.inline"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(DesignSystem.Colors.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                model.startCodeReview(source: model.branchReviewSource, target: model.branchReviewTarget)
            } label: {
                Label(L10n("codereview.startReview"), systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.ai)
            .disabled(
                model.branchReviewSource.isEmpty
                    || model.branchReviewTarget.isEmpty
                    || model.branchReviewSource == model.branchReviewTarget
            )
            .help(L10n("codereview.startReview.hint"))
            .onAppear { model.ensureBranchReviewSelections() }
        }
    }
}
