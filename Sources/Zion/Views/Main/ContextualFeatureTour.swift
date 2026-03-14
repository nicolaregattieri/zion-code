import SwiftUI

enum FeatureTourAnchorID: Hashable {
    case recentRepositories
    case workspace
    case zenToolbar
    case worktrees
}

enum ContextualFeatureTourStep: Int, CaseIterable {
    case recentRepositories
    case workspace
    case worktrees
    case zenToolbar

    var anchorID: FeatureTourAnchorID {
        switch self {
        case .recentRepositories: return .recentRepositories
        case .workspace: return .workspace
        case .zenToolbar: return .zenToolbar
        case .worktrees: return .worktrees
        }
    }

    var titleKey: String {
        switch self {
        case .recentRepositories:
            return "featureTour.recent.title"
        case .workspace:
            return "featureTour.workspace.title"
        case .zenToolbar:
            return "featureTour.zen.title"
        case .worktrees:
            return "featureTour.worktrees.title"
        }
    }

    var bodyKey: String {
        switch self {
        case .recentRepositories:
            return "featureTour.recent.body"
        case .workspace:
            return "featureTour.workspace.body"
        case .zenToolbar:
            return "featureTour.zen.body"
        case .worktrees:
            return "featureTour.worktrees.body"
        }
    }

    var supplementaryKey: String? {
        switch self {
        case .worktrees:
            return "featureTour.ai.optional"
        case .recentRepositories, .workspace, .zenToolbar:
            return nil
        }
    }

    /// SF Symbol name shown inline in the card to help users identify the button.
    var iconHint: String? {
        switch self {
        case .zenToolbar:
            return "arrow.up.left.and.arrow.down.right"
        case .recentRepositories, .workspace, .worktrees:
            return nil
        }
    }
}

struct FeatureTourFramePreferenceKey: PreferenceKey {
    static let defaultValue: [FeatureTourAnchorID: CGRect] = [:]

    static func reduce(value: inout [FeatureTourAnchorID: CGRect], nextValue: () -> [FeatureTourAnchorID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func featureTourAnchor(_ id: FeatureTourAnchorID) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: FeatureTourFramePreferenceKey.self,
                    value: [id: proxy.frame(in: .named("featureTour"))]
                )
            }
        )
    }
}

private struct FeatureTourSpotlightShape: Shape {
    let cutoutRect: CGRect
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addPath(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .path(in: cutoutRect)
        )
        return path
    }
}

struct ContextualFeatureTourOverlay: View {
    let steps: [ContextualFeatureTourStep]
    let currentIndex: Int
    let anchorFrames: [FeatureTourAnchorID: CGRect]
    let onBack: () -> Void
    let onNext: () -> Void
    let onSkip: () -> Void

    private let spotlightInset: CGFloat = 10
    private let cardWidth: CGFloat = 340

    private var currentStep: ContextualFeatureTourStep {
        steps[currentIndex]
    }

    private var targetFrame: CGRect? {
        anchorFrames[currentStep.anchorID]?.insetBy(dx: -spotlightInset, dy: -spotlightInset)
    }

    private var hasSpotlight: Bool {
        targetFrame != nil
    }

    var body: some View {
        GeometryReader { geometry in
            let containerSize = geometry.size

            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSkip()
                    }

                if let frame = targetFrame {
                    FeatureTourSpotlightShape(
                        cutoutRect: frame,
                        cornerRadius: DesignSystem.Spacing.cardCornerRadius + 2
                    )
                    .fill(Color.black.opacity(0.58), style: FillStyle(eoFill: true))

                    RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius + 2, style: .continuous)
                        .stroke(Color.white.opacity(0.45), lineWidth: 1.5)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)

                    tourCard(in: containerSize, targetFrame: frame)
                } else {
                    Color.black.opacity(0.58)

                    tourCardNoSpotlight(in: containerSize)
                }
            }
            .compositingGroup()
            .ignoresSafeArea()
            .background {
                Button("") {
                    onSkip()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .frame(width: 0, height: 0)
                .opacity(0)
            }
        }
        .transition(.opacity)
        .zIndex(999)
    }

    private func tourCardNoSpotlight(in containerSize: CGSize) -> some View {
        let width = min(cardWidth, max(containerSize.width - 32, 240))
        let estimatedHeight: CGFloat = 228
        let position = CGPoint(
            x: containerSize.width - width / 2 - 16,
            y: estimatedHeight / 2 + 48
        )

        return tourCardContent(in: containerSize)
            .position(position)
    }

    private func tourCard(in containerSize: CGSize, targetFrame: CGRect) -> some View {
        let position = cardPosition(in: containerSize, targetFrame: targetFrame)

        return tourCardContent(in: containerSize)
            .position(position)
    }

    private func tourCardContent(in containerSize: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(L10n("featureTour.stepLabel", currentIndex + 1, steps.count))
                    .font(DesignSystem.Typography.labelBold)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button {
                    onSkip()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DesignSystem.Typography.bodyLarge)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L10n("featureTour.skip"))
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    if let iconHint = currentStep.iconHint {
                        Image(systemName: iconHint)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(DesignSystem.Colors.actionPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous))
                    }
                    Text(L10n(currentStep.titleKey))
                        .font(DesignSystem.Typography.sheetTitle)
                }
                Text(L10n(currentStep.bodyKey))
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let supplementaryKey = currentStep.supplementaryKey {
                    Text(L10n(supplementaryKey))
                        .font(DesignSystem.Typography.bodySmallSemibold)
                        .foregroundStyle(DesignSystem.Colors.ai)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Button(L10n("featureTour.skip")) {
                    onSkip()
                }
                .buttonStyle(.plain)
                .font(DesignSystem.Typography.bodySmall)
                .foregroundStyle(.secondary)

                if currentIndex > 0 {
                    Button(L10n("featureTour.back")) {
                        onBack()
                    }
                    .buttonStyle(.bordered)
                }

                Spacer(minLength: 0)

                Button(currentIndex == steps.count - 1 ? L10n("featureTour.done") : L10n("featureTour.next")) {
                    onNext()
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.actionPrimary)
            }
        }
        .padding(16)
        .frame(width: min(cardWidth, max(containerSize.width - 32, 240)), alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius, style: .continuous)
                .stroke(DesignSystem.Colors.glassBorderLight, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 18, y: 10)
    }

    private func cardPosition(in containerSize: CGSize, targetFrame: CGRect) -> CGPoint {
        let width = min(cardWidth, max(containerSize.width - 32, 240))
        let halfWidth = width / 2
        let minX = halfWidth + 16
        let maxX = max(containerSize.width - halfWidth - 16, minX)
        let x = min(max(targetFrame.midX, minX), maxX)

        let estimatedHeight: CGFloat = 228
        let spaceBelow = containerSize.height - targetFrame.maxY
        let y: CGFloat

        if spaceBelow > estimatedHeight + 24 {
            y = min(targetFrame.maxY + estimatedHeight / 2 + 22, containerSize.height - estimatedHeight / 2 - 16)
        } else {
            y = max(targetFrame.minY - estimatedHeight / 2 - 22, estimatedHeight / 2 + 16)
        }

        return CGPoint(x: x, y: y)
    }
}

enum FeatureTourLaunchPolicy {
    static func shouldAutoStartFirstRepositoryTour(
        hasOpenedRepositoryOnce: Bool,
        hasCompletedFeatureTour: Bool
    ) -> Bool {
        !hasOpenedRepositoryOnce && !hasCompletedFeatureTour
    }

    static func inferredExistingRepositoryHistory(from recentRepositoriesData: Data?) -> Bool {
        guard let recentRepositoriesData else { return false }
        return !recentRepositoriesData.isEmpty
    }
}
