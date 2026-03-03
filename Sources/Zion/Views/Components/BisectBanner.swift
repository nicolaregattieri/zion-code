import SwiftUI

struct BisectBanner: View {
    @Bindable var model: RepositoryViewModel

    var body: some View {
        switch model.bisectPhase {
        case .inactive:
            EmptyView()
        case .awaitingGoodCommit:
            awaitingGoodBanner
        case .active(let currentHash, let stepsRemaining):
            activeBanner(currentHash: currentHash, stepsRemaining: stepsRemaining)
        case .foundCulprit(let commitHash):
            foundBanner(commitHash: commitHash)
        }
    }

    // MARK: - Awaiting Good Commit

    private var awaitingGoodBanner: some View {
        HStack(spacing: 16) {
            Image(systemName: "arrow.trianglehead.branch")
                .font(.title3)
                .foregroundStyle(DesignSystem.Colors.info)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n("bisect.banner.pickGood.title"))
                    .font(DesignSystem.Typography.sheetTitle)
                Text(L10n("bisect.banner.pickGood.subtitle"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(L10n("bisect.abort")) {
                model.bisectAbort()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(16)
        .background(DesignSystem.Colors.statusBlueBg)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Active Bisect

    private func activeBanner(currentHash: String, stepsRemaining: Int) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "arrow.trianglehead.branch")
                .font(.title3)
                .foregroundStyle(DesignSystem.Colors.info)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n("bisect.banner.active.title", String(currentHash.prefix(8))))
                    .font(DesignSystem.Typography.sheetTitle)
                if stepsRemaining > 0 {
                    Text(L10n("bisect.banner.active.subtitle", "\(stepsRemaining)"))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                Button {
                    model.bisectMarkGood()
                } label: {
                    Label(L10n("bisect.good"), systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.success)
                .controlSize(.small)

                Button {
                    model.bisectMarkBad()
                } label: {
                    Label(L10n("bisect.bad"), systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.destructive)
                .controlSize(.small)

                Button(L10n("bisect.skip")) {
                    model.bisectSkip()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(L10n("bisect.abort")) {
                    model.bisectAbort()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Found Culprit

    private func foundBanner(commitHash: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(DesignSystem.Colors.destructive)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n("bisect.banner.found.title", String(commitHash.prefix(8))))
                        .font(DesignSystem.Typography.sheetTitle)
                }

                Spacer()

                HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                    Button {
                        model.selectCommit(commitHash)
                    } label: {
                        Label(L10n("bisect.viewCommit"), systemImage: "eye")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(L10n("bisect.done")) {
                        model.bisectAbort()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            if model.isBisectAILoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n("bisect.ai.loading"))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 36)
            } else if !model.bisectAIExplanation.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(DesignSystem.Colors.ai)
                    Text(model.bisectAIExplanation)
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.leading, 36)
            }
        }
        .padding(16)
        .background(DesignSystem.Colors.destructiveBg)
        .overlay(alignment: .bottom) { Divider() }
    }
}
