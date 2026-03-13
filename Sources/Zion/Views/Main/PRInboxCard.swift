import SwiftUI

enum PRInboxSurface {
    case forReview
    case allOpen
}

struct PRInboxAccessState: Equatable {
    let icon: String
    let message: String?
    let hint: String?

    var isAvailable: Bool { message == nil }

    static let available = PRInboxAccessState(icon: "checkmark.circle", message: nil, hint: nil)
}

private enum PRTab: String, CaseIterable {
    case forReview
    case allOpen
}

struct PRInboxCard: View {
    var model: RepositoryViewModel
    @State private var isExpanded: Bool = true
    @State private var selectedTab: PRTab = .forReview
    @State private var isCheckingHostingAccess: Bool = true
    @State private var forReviewAccessState = PRInboxAccessState.available
    @State private var allOpenAccessState = PRInboxAccessState.available

    private var totalCount: Int {
        switch selectedTab {
        case .forReview: return model.prReviewQueue.count
        case .allOpen: return allOpenPRs.count
        }
    }

    private var allOpenPRs: [GitHubPRInfo] {
        guard allOpenAccessState.isAvailable else { return [] }
        let reviewIDs = Set(model.prReviewQueue.map(\.pr.id))
        return model.pullRequests.filter { !reviewIDs.contains($0.id) }
    }

    private var hostingRefreshKey: String {
        let remoteSignature = model.remotes.map(\.url).joined(separator: "|")
        return "\(model.repositoryURL?.path ?? "no-repo")|\(remoteSignature)"
    }

    var body: some View {
        GlassCard(spacing: 10) {
            CardHeader(L10n("pr.inbox.title"), icon: "arrow.triangle.pull") {
                HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                    if totalCount > 0 {
                        Text("\(totalCount)")
                            .font(DesignSystem.Typography.labelBold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(DesignSystem.Colors.ai.opacity(0.7)))
                    }

                    Button {
                        withAnimation(DesignSystem.Motion.panel) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(DesignSystem.Typography.metaBold)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .animation(DesignSystem.Motion.panel, value: isExpanded)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
                    .accessibilityLabel(isExpanded ? L10n("accessibility.collapse") : L10n("accessibility.expand"))
                }
            }

            if isExpanded {
                Picker("", selection: $selectedTab) {
                    Text(L10n("pr.tab.forReview") + " (\(model.prReviewQueue.count))")
                        .tag(PRTab.forReview)
                    Text(L10n("pr.tab.allOpen") + " (\(allOpenPRs.count))")
                        .tag(PRTab.allOpen)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)

                switch selectedTab {
                case .forReview:
                    forReviewContent
                case .allOpen:
                    allOpenContent
                }
            }
        }
        .padding(.horizontal, 10)
        .task(id: hostingRefreshKey) {
            await refreshHostingAccessState()
        }
    }

    @ViewBuilder
    private var forReviewContent: some View {
        if isCheckingHostingAccess {
            HStack {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Spacer()
            }
            .padding(.vertical, 8)
        } else if let message = forReviewAccessState.message {
            tabEmptyState(
                icon: forReviewAccessState.icon,
                message: message,
                hint: forReviewAccessState.hint
            )
        } else if model.prReviewQueue.isEmpty {
            tabEmptyState(
                icon: "tray",
                message: L10n("pr.inbox.empty"),
                hint: nil
            )
        } else {
            VStack(spacing: 4) {
                ForEach(model.prReviewQueue) { item in
                    PRInboxRow(item: item) {
                        model.openPRInCodeReview(item)
                    }
                }
            }

            if model.prReviewQueue.contains(where: { $0.status == .pending }) {
                Button {
                    model.reviewAllPRs()
                } label: {
                    Label(L10n("pr.inbox.reviewAll"), systemImage: "sparkles")
                        .font(DesignSystem.Typography.labelMedium)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(DesignSystem.Colors.ai)
            }
        }
    }

    @ViewBuilder
    private var allOpenContent: some View {
        if isCheckingHostingAccess {
            HStack {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Spacer()
            }
            .padding(.vertical, 8)
        } else if let message = allOpenAccessState.message {
            tabEmptyState(
                icon: allOpenAccessState.icon,
                message: message,
                hint: allOpenAccessState.hint
            )
        } else if allOpenPRs.isEmpty {
            tabEmptyState(
                icon: "checkmark.circle",
                message: L10n("pr.allOpen.empty"),
                hint: nil
            )
        } else {
            VStack(spacing: 4) {
                ForEach(allOpenPRs) { pr in
                    PROpenRow(pr: pr) {
                        model.openPRFromInfo(pr)
                    }
                }
            }
        }
    }

    private func tabEmptyState(icon: String, message: String, hint: String?) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            Text(message)
                .font(DesignSystem.Typography.bodySmall)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let hint {
                Text(hint)
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func refreshHostingAccessState() async {
        isCheckingHostingAccess = true

        guard let (provider, _) = model.detectHostingProvider() else {
            let unavailable = PRInboxAccessState(
                icon: "link.badge.questionmark",
                message: L10n("hosting.notConnected"),
                hint: L10n("pr.inbox.providerHint")
            )
            forReviewAccessState = unavailable
            allOpenAccessState = unavailable
            isCheckingHostingAccess = false
            return
        }

        let hasToken = await provider.hasToken()
        let githubStatus = provider.kind == .github ? GitHubClient.checkGHStatus() : nil
        forReviewAccessState = Self.accessState(
            for: .forReview,
            providerKind: provider.kind,
            hasToken: hasToken,
            githubStatus: githubStatus
        )
        allOpenAccessState = Self.accessState(
            for: .allOpen,
            providerKind: provider.kind,
            hasToken: hasToken,
            githubStatus: githubStatus
        )

        isCheckingHostingAccess = false
    }

    nonisolated static func accessState(
        for surface: PRInboxSurface,
        providerKind: GitHostingKind?,
        hasToken: Bool,
        githubStatus: (installed: Bool, authenticated: Bool)? = nil
    ) -> PRInboxAccessState {
        guard let providerKind else {
            return PRInboxAccessState(
                icon: "link.badge.questionmark",
                message: L10n("hosting.notConnected"),
                hint: L10n("pr.inbox.providerHint")
            )
        }

        if hasToken {
            return .available
        }

        if surface == .allOpen && providerKind.supportsAnonymousOpenPullRequests {
            return .available
        }

        switch providerKind {
        case .github:
            let status = githubStatus ?? GitHubClient.checkGHStatus()
            if !status.installed {
                return PRInboxAccessState(
                    icon: "exclamationmark.triangle",
                    message: L10n("pr.gh.notInstalled"),
                    hint: L10n("pr.gh.notInstalled.hint")
                )
            }
            if !status.authenticated {
                return PRInboxAccessState(
                    icon: "person.crop.circle.badge.questionmark",
                    message: L10n("pr.gh.notAuthenticated"),
                    hint: L10n("pr.gh.notAuthenticated.hint")
                )
            }
            return PRInboxAccessState(
                icon: "person.crop.circle.badge.questionmark",
                message: L10n("pr.inbox.authRequired", providerKind.label),
                hint: L10n("pr.inbox.authRequired.hint", providerKind.label)
            )
        case .gitlab, .bitbucket, .azureDevOps:
            return PRInboxAccessState(
                icon: "person.crop.circle.badge.questionmark",
                message: L10n("pr.inbox.authRequired", providerKind.label),
                hint: L10n("pr.inbox.authRequired.hint", providerKind.label)
            )
        }
    }
}

private struct PROpenRow: View {
    let pr: GitHubPRInfo
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                authorAvatar

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                        Text("#\(pr.number)")
                            .font(DesignSystem.Typography.monoLabelBold)
                            .foregroundStyle(.secondary)
                        Text(pr.title)
                            .font(DesignSystem.Typography.bodyMedium)
                            .lineLimit(1)
                    }

                    HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                        Text("@\(pr.author)")
                            .font(DesignSystem.Typography.monoMeta)
                            .foregroundStyle(.tertiary)

                        Text("\(pr.headBranch) \u{2192} \(pr.baseBranch)")
                            .font(DesignSystem.Typography.monoMeta)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)

                        if pr.isDraft {
                            Text(L10n("pr.draft"))
                                .font(DesignSystem.Typography.micro)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(DesignSystem.Colors.glassHover)
                                .foregroundStyle(.secondary)
                                .clipShape(Capsule())
                        }
                    }
                }

                Spacer(minLength: 4)

                Image(systemName: "sparkles")
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundStyle(DesignSystem.Colors.ai)

                Image(systemName: "chevron.right")
                    .font(DesignSystem.Typography.micro)
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                    .fill(isHovered ? DesignSystem.Colors.glassHover : DesignSystem.Colors.glassMinimal)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                    .stroke(DesignSystem.Colors.glassHover, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in isHovered = h }
        .contextMenu {
            Button {
                if let url = URL(string: pr.url) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label(L10n("pr.inbox.openProvider"), systemImage: "link")
            }
        }
    }

    private var authorAvatar: some View {
        let initial = pr.author.prefix(1).uppercased()
        let hue = Double(abs(pr.author.hashValue) % 360) / 360.0

        return Text(initial)
            .font(DesignSystem.Typography.labelBold)
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(Color(hue: hue, saturation: 0.6, brightness: 0.8)))
    }
}
