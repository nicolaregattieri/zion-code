import SwiftUI

extension GraphScreen {
    @ViewBuilder
    var commitDetailsPane: some View {
        if showingPendingChanges {
            inlineChangesPane
        } else if let selectedCommitID = model.selectedCommitID {
            GlassCard(spacing: 0) {
                CardHeader(L10n("Detalhes"), icon: "doc.text.magnifyingglass") {
                    HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                        if model.isAIConfigured {
                            Button {
                                model.reviewCommitChanges(commitID: selectedCommitID)
                            } label: {
                                if model.reviewingCommitID == selectedCommitID {
                                    ProgressView()
                                        .controlSize(.mini)
                                        .frame(width: 10, height: 10)
                                } else {
                                    Image(systemName: "sparkles")
                                        .font(DesignSystem.Typography.labelBold)
                                }
                            }
                            .buttonStyle(.plain)
                            .cursorArrow()
                            .foregroundStyle(DesignSystem.Colors.ai)
                            .help(L10n("graph.commit.review"))
                            .accessibilityLabel(L10n("graph.commit.review"))
                        }

                        if model.cachedReviewFindings(for: selectedCommitID) != nil {
                            Text(L10n("graph.commit.review.cached"))
                                .font(DesignSystem.Typography.metaBold)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(DesignSystem.Colors.glassSubtle)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(DesignSystem.Colors.glassBorderDark, lineWidth: 1)
                                )
                                .foregroundStyle(.secondary)
                        }

                        Text(String(selectedCommitID.prefix(8)))
                            .font(DesignSystem.Typography.monoLabel)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)

                if model.isAIConfigured {
                    HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                        detailTabButton(
                            title: L10n("graph.commit.review.tab.details"),
                            isSelected: model.selectedCommitDetailTab == .details
                        ) {
                            model.selectedCommitDetailTab = .details
                        }

                        detailTabButton(
                            title: L10n("graph.commit.review.tab.ai"),
                            isSelected: model.selectedCommitDetailTab == .aiReview
                        ) {
                            model.selectedCommitDetailTab = .aiReview
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }

                Divider()

                ScrollView {
                    CommitDetailContent(rawDetails: model.commitDetails, model: model, commitID: selectedCommitID)
                        .padding(12)
                }
            }
        } else {
            GlassCard(spacing: 0) {
                VStack(spacing: 16) {
                    Image(systemName: "arrow.left.circle")
                        .font(DesignSystem.Typography.heroIcon)
                        .foregroundStyle(.tertiary)
                    Text(L10n("Selecione um commit para ver detalhes"))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            }
        }
    }

    func detailTabButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DesignSystem.Typography.labelSemibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous)
                        .fill(isSelected ? DesignSystem.Colors.selectionBackground : DesignSystem.Colors.glassSubtle)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous)
                        .stroke(isSelected ? DesignSystem.Colors.selectionBorder : DesignSystem.Colors.glassBorderDark, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .cursorArrow()
    }
}
