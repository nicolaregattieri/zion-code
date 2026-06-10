import SwiftUI

struct OpsCommitCard: View {
    @Bindable var model: RepositoryViewModel
    let performGitAction: (String, String, Bool, @escaping () -> Void) -> Void
    var zionModeEnabled: Bool

    var body: some View {
        GlassCard(spacing: 12) {
            CardHeader(L10n("Novo Commit"), icon: "plus.square.on.square", subtitle: L10n("Gravar alteracoes no repositorio"))

            VStack(spacing: 10) {
                if !model.uncommittedChanges.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L10n("Arquivos alterados")).font(DesignSystem.Typography.label).foregroundStyle(.secondary)
                            Spacer()
                            HStack(spacing: 12) {
                                Button(L10n("Selecionar Tudo")) { model.stageAllFiles() }
                                    .buttonStyle(.plain)
                                    .font(DesignSystem.Typography.labelBold)
                                    .foregroundStyle(Color.accentColor)

                                Button(L10n("Desmarcar Tudo")) { model.unstageAllFiles() }
                                    .buttonStyle(.plain)
                                    .font(DesignSystem.Typography.labelBold)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(model.uncommittedChanges, id: \.self) { change in
                                    FileStatusRow(model: model, line: change, performGitAction: performGitAction)
                                }
                            }
                        }
                        .frame(maxHeight: 160)
                        .padding(4)
                        .background(DesignSystem.Colors.glassOverlay)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius))
                    }
                }

                HStack(alignment: .bottom, spacing: 8) {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $model.commitMessageInput)
                            .font(DesignSystem.Typography.monoBody)
                            .lineSpacing(4)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(DesignSystem.Colors.glassInset)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous)
                                    .stroke(DesignSystem.Colors.glassStroke, lineWidth: 1)
                            )
                            .frame(minHeight: 130, maxHeight: 170)

                        if model.commitMessageInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(L10n("Mensagem do commit..."))
                                .font(DesignSystem.Typography.monoBody)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .allowsHitTesting(false)
                        }
                    }

                    Button {
                        model.suggestCommitMessage()
                    } label: {
                        if model.isGeneratingAIMessage {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "sparkles")
                                .font(DesignSystem.Typography.body)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(DesignSystem.Colors.ai)
                    .disabled(model.isGeneratingAIMessage)
                    .accessibilityLabel(L10n("accessibility.commit.suggestMessage"))
                    .help(model.isAIConfigured ? L10n("Gerar mensagem com IA") : L10n("Sugerir mensagem de commit"))
                    .onChange(of: model.suggestedCommitMessage) { _, newValue in
                        if !newValue.isEmpty {
                            model.commitMessageInput = newValue
                        }
                    }
                }

                if let warning = model.aiCommitWarning, !model.aiQuotaExceeded {
                    HStack(alignment: .top, spacing: DesignSystem.Spacing.iconInlineGap) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(DesignSystem.Typography.label)
                            .foregroundStyle(DesignSystem.Colors.warning)
                        Text(warning)
                            .font(DesignSystem.Typography.labelMedium)
                            .foregroundStyle(DesignSystem.Colors.warning)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                }

                HStack {
                    Toggle(L10n("Corrigir ultimo commit (Amend)"), isOn: $model.amendLastCommit)
                        .toggleStyle(.checkbox)
                        .font(DesignSystem.Typography.label)
                    Spacer()

                    if model.isAIConfigured {
                        Button {
                            model.reviewStagedChanges()
                        } label: {
                            if model.isGeneratingAIMessage && !model.isReviewVisible {
                                ProgressView().controlSize(.small).frame(width: 12, height: 12)
                            } else {
                                Label(L10n("Review"), systemImage: "sparkles")
                                    .font(DesignSystem.Typography.labelBold)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(DesignSystem.Colors.ai)
                        .disabled(model.isGeneratingAIMessage)
                        .help(L10n("Revisar codigo com IA"))

                        Button {
                            model.suggestCommitSplit()
                        } label: {
                            if model.isGeneratingAIMessage && !model.isSplitVisible {
                                ProgressView().controlSize(.small).frame(width: 12, height: 12)
                            } else {
                                Label(L10n("Split"), systemImage: "sparkles")
                                    .font(DesignSystem.Typography.labelBold)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(DesignSystem.Colors.ai)
                        .disabled(model.isGeneratingAIMessage)
                        .help(L10n("Sugerir divisao de commits com IA"))
                    }
                }

                if zionModeEnabled && model.isGeneratingAIMessage {
                    NeonProgressLine(
                        gradient: DesignSystem.ZionMode.neonAIGradient,
                        mode: .pulse
                    )
                    .padding(.top, 4)
                    .transition(.opacity.animation(DesignSystem.Motion.panel))
                }

                // AI Code Review Results
                if model.isReviewVisible && !model.aiReviewFindings.isEmpty {
                    ReviewFindingsView(
                        findings: model.aiReviewFindings,
                        tintColor: DesignSystem.Colors.ai,
                        onOpenFile: { file, snippet in
                            model.openFileInEditor(relativePath: file, highlightQuery: snippet)
                        },
                        onDismiss: {
                            model.isReviewVisible = false
                        }
                    )
                }

                // AI Commit Split Suggestions
                if model.isSplitVisible && !model.aiCommitSplitSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "sparkles").foregroundStyle(DesignSystem.Colors.commitSplit)
                            Text(L10n("Sugestao de Split")).font(DesignSystem.Typography.bodyMedium)
                            Spacer()
                            Button { model.isSplitVisible = false } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n("accessibility.dismiss"))
                        }
                        ForEach(model.aiCommitSplitSuggestions) { suggestion in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(suggestion.message)
                                    .font(DesignSystem.Typography.monoSmall)
                                HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                                    ForEach(suggestion.files, id: \.self) { file in
                                        Text(file)
                                            .font(DesignSystem.Typography.monoMeta)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(DesignSystem.Colors.commitSplit.opacity(0.1))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DesignSystem.Colors.glassMinimal)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
                        }
                    }
                    .padding(10)
                    .background(DesignSystem.Colors.glassSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius))
                }

                // Pre-Commit Review Gate Card
                if model.preCommitReviewPending && model.isReviewVisible && !model.aiReviewFindings.isEmpty {
                    PreCommitCheckCard(model: model) {
                        model.dismissPreCommitReview()
                        performGitAction(L10n("Commit"), L10n("commit.confirm.staged"), false) {
                            model.commit(message: model.commitMessageInput)
                        }
                    } onFixIssues: {
                        model.preCommitReviewPending = false
                    }
                }

                if model.preCommitReviewPending && model.isGeneratingAIMessage {
                    HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                        ProgressView().controlSize(.small)
                        Text(L10n("precommit.reviewing"))
                            .font(DesignSystem.Typography.bodyMedium)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(DesignSystem.Colors.ai.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius))
                }

                Button(action: {
                    if model.preCommitReviewEnabled && model.isAIConfigured && !model.preCommitReviewPending {
                        model.runPreCommitReview()
                    } else if !model.preCommitReviewPending {
                        performGitAction(L10n("Commit"), L10n("commit.confirm.staged"), false) {
                            model.commit(message: model.commitMessageInput)
                        }
                    }
                }) {
                    Label(L10n("Fazer Commit"), systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(DesignSystem.Colors.actionPrimary)
                .disabled(model.commitMessageInput.clean.isEmpty || model.preCommitReviewPending || !model.hasStagedChanges)
            }
        }
    }
}
