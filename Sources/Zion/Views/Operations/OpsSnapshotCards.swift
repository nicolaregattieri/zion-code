import SwiftUI

// MARK: - Stash Card

struct OpsStashCard: View {
    @Bindable var model: RepositoryViewModel
    let performGitAction: (String, String, Bool, @escaping () -> Void) -> Void

    var body: some View {
        GlassCard(spacing: 10, expanding: true) {
            CardHeader(L10n("Stash"), icon: "archivebox", subtitle: L10n("Salvar e restaurar alteracoes temporarias"))
            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                TextField(L10n("mensagem do stash"), text: $model.stashMessageInput).textFieldStyle(.roundedBorder)
                if model.isAIConfigured {
                    Button {
                        model.suggestStashMessage()
                    } label: {
                        if model.isGeneratingAIMessage {
                            ProgressView().controlSize(.small).frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "sparkles").font(DesignSystem.Typography.body)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(DesignSystem.Colors.ai)
                    .disabled(model.isGeneratingAIMessage)
                    .accessibilityLabel(L10n("accessibility.stash.suggestMessage"))
                    .help(L10n("Gerar mensagem com IA"))
                }
                Button(L10n("Criar stash")) {
                    performGitAction(L10n("Criar stash"), L10n("Salvar alteracoes locais no stash?"), false) { model.createStash() }
                }.buttonStyle(.borderedProminent).tint(DesignSystem.Colors.actionPrimary)
            }
            if model.stashes.isEmpty {
                Text(L10n("stash.empty.hint"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Picker(L10n("Stash"), selection: $model.selectedStash) {
                ForEach(model.stashes, id: \.self) { stash in Text(stash).tag(stash) }
            }.pickerStyle(.menu).disabled(model.stashes.isEmpty)
            HStack {
                Button(L10n("Apply")) { performGitAction(L10n("Apply stash"), L10n("Aplicar o stash selecionado?"), false) { model.applySelectedStash() } }.buttonStyle(.bordered)
                Button(L10n("Pop")) { performGitAction(L10n("Pop stash"), L10n("Aplicar e remover o stash selecionado?"), false) { model.popSelectedStash() } }.buttonStyle(.bordered)
                Button(L10n("Drop")) {
                    let reference = model.selectedStash.clean.isEmpty ? "stash@{0}" : model.selectedStash.clean
                    let message = L10n("stash.drop.confirm.withCount", reference, "\(model.stashes.count)")
                    performGitAction(L10n("Drop stash"), message, true) { model.dropSelectedStash() }
                }.buttonStyle(.bordered).tint(DesignSystem.Colors.destructive)
            }.disabled(model.stashes.isEmpty)
        }
    }
}

// MARK: - Tags Card

struct OpsTagsCard: View {
    @Bindable var model: RepositoryViewModel
    let performGitAction: (String, String, Bool, @escaping () -> Void) -> Void

    var body: some View {
        GlassCard(spacing: 10, expanding: true) {
            CardHeader(L10n("Tags"), icon: "tag", subtitle: L10n("Marcar pontos importantes no historico"))
            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                TextField("v1.0.0", text: $model.tagInput).textFieldStyle(.roundedBorder)
                Button(L10n("Criar")) {
                    model.isTagDetailSheetVisible = true
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.actionPrimary)
                Button(L10n("Remover")) { performGitAction(L10n("Remover tag"), L10n("Deseja remover a tag informada?"), true) { model.deleteTag() } }.buttonStyle(.bordered).tint(DesignSystem.Colors.destructive)
            }
            if model.tags.isEmpty {
                Text(L10n("tags.empty.hint"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: $model.isTagDetailSheetVisible) {
            TagDetailSheet(model: model)
        }
    }
}

// MARK: - Recovery Vault Card

struct OpsRecoveryVaultCard: View {
    var model: RepositoryViewModel
    let performGitAction: (String, String, Bool, @escaping () -> Void) -> Void
    @State private var visibleCount: Int = 16

    var body: some View {
        GlassCard(spacing: 10, expanding: true) {
            CardHeader(L10n("recovery.title"), icon: "lifepreserver", subtitle: L10n("recovery.subtitle")) {
                Button {
                    model.refreshRecoverySnapshots(includeDangling: true)
                } label: {
                    if model.isRecoverySnapshotsLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(DesignSystem.Typography.labelBold)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n("accessibility.recovery.refresh"))
                .help(L10n("recovery.refresh"))
            }

            if !model.recoverySnapshotsStatus.clean.isEmpty {
                Text(model.recoverySnapshotsStatus)
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
            }

            if model.recoverySnapshots.isEmpty && !model.isRecoverySnapshotsLoading {
                Text(L10n("recovery.empty"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(model.recoverySnapshots.prefix(visibleCount)) { snapshot in
                            HStack(spacing: DesignSystem.Spacing.toolbarItemGap) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                                        Text(snapshot.shortHash)
                                            .font(DesignSystem.Typography.monoLabelBold)
                                            .foregroundStyle(.primary)
                                        Text(L10n(snapshot.source.l10nKey))
                                            .font(DesignSystem.Typography.metaBold)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(DesignSystem.Colors.glassInset)
                                            .clipShape(Capsule())
                                    }
                                    Text(snapshot.subject)
                                        .font(DesignSystem.Typography.label)
                                        .lineLimit(1)
                                    Text(snapshot.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(DesignSystem.Typography.meta)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()

                                HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                                    Button(L10n("recovery.copy")) {
                                        model.copyRecoverySnapshotReference(snapshot)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button(L10n("recovery.restore")) {
                                        performGitAction(
                                            L10n("recovery.restore"),
                                            L10n("recovery.restore.confirm", snapshot.shortHash),
                                            true
                                        ) {
                                            model.restoreRecoverySnapshot(snapshot)
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .tint(DesignSystem.Colors.actionPrimary)
                                }
                            }
                            .padding(8)
                            .background(DesignSystem.Colors.glassMinimal)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
                        }
                        if model.recoverySnapshots.count > visibleCount {
                            Button(L10n("recovery.showMore", model.recoverySnapshots.count - visibleCount)) {
                                visibleCount += 16
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 220)
            }
        }
        .onAppear {
            if model.recoverySnapshots.isEmpty {
                model.refreshRecoverySnapshots(includeDangling: true)
            }
        }
    }
}
