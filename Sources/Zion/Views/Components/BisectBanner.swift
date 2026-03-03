import SwiftUI

struct BisectBanner: View {
    @Bindable var model: RepositoryViewModel

    var body: some View {
        Group {
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
        .animation(DesignSystem.Motion.detail, value: model.bisectPhase)
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
            .help(L10n("bisect.abort"))
            .accessibilityLabel(L10n("bisect.abort"))
        }
        .padding(16)
        .background(DesignSystem.Colors.statusBlueBg)
        .overlay(alignment: .bottom) { Divider() }
        .transition(.opacity)
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
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .help(L10n("bisect.good.hint"))
                .accessibilityLabel(L10n("bisect.good"))

                Button {
                    model.bisectMarkBad()
                } label: {
                    Label(L10n("bisect.bad"), systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.destructive)
                .controlSize(.small)
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .help(L10n("bisect.bad.hint"))
                .accessibilityLabel(L10n("bisect.bad"))

                Button(L10n("bisect.skip")) {
                    model.bisectSkip()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .help(L10n("bisect.skip.hint"))
                .accessibilityLabel(L10n("bisect.skip"))

                Button(L10n("bisect.abort")) {
                    model.bisectAbort()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(L10n("bisect.abort"))
                .accessibilityLabel(L10n("bisect.abort"))
            }
        }
        .padding(16)
        .background(DesignSystem.Colors.statusBlueBg)
        .overlay(alignment: .bottom) { Divider() }
        .transition(.opacity)
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
                    .help(L10n("bisect.viewCommit"))
                    .accessibilityLabel(L10n("bisect.viewCommit"))

                    Button(L10n("bisect.done")) {
                        model.bisectFinish()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help(L10n("bisect.done"))
                    .accessibilityLabel(L10n("bisect.done"))
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
        .transition(.opacity)
    }
}
