import SwiftUI

private enum PRTab: String, CaseIterable {
    case forReview
    case allOpen
}

struct PRInboxCard: View {
    var model: RepositoryViewModel
    @State private var isExpanded: Bool = true
    @State private var selectedTab: PRTab = .forReview

    private var totalCount: Int {
        switch selectedTab {
        case .forReview: return model.prReviewQueue.count
        case .allOpen: return allOpenPRs.count
        }
    }

    private var allOpenPRs: [GitHubPRInfo] {
        let reviewIDs = Set(model.prReviewQueue.map(\.pr.id))
        return model.pullRequests.filter { !reviewIDs.contains($0.id) }
    }

    var body: some View {
        GlassCard(spacing: 10) {
            CardHeader(L10n("pr.inbox.title"), icon: "arrow.triangle.pull") {
                HStack(spacing: 6) {
                    if totalCount > 0 {
                        Text("\(totalCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.indigo.opacity(0.7)))
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .animation(.easeInOut(duration: 0.2), value: isExpanded)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
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
    }

    @ViewBuilder
    private var forReviewContent: some View {
        if model.prReviewQueue.isEmpty {
            tabEmptyState(
                icon: "tray",
                message: L10n("pr.inbox.empty"),
                hint: L10n("pr.inbox.setup.hint")
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
                        .font(.system(size: 10, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.indigo)
            }
        }
    }

    @ViewBuilder
    private var allOpenContent: some View {
        if allOpenPRs.isEmpty {
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
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let hint {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

private struct PROpenRow: View {
    let pr: GitHubPRInfo
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                authorAvatar

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("#\(pr.number)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(pr.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }

                    HStack(spacing: 6) {
                        Text("@\(pr.author)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)

                        Text("\(pr.headBranch) \u{2192} \(pr.baseBranch)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)

                        if pr.isDraft {
                            Text(L10n("pr.draft"))
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.gray.opacity(0.2))
                                .foregroundStyle(.secondary)
                                .clipShape(Capsule())
                        }
                    }
                }

                Spacer(minLength: 4)

                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(.purple)

                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? DesignSystem.Colors.glassHover : DesignSystem.Colors.glassMinimal)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                Label(L10n("pr.inbox.openGitHub"), systemImage: "link")
            }
        }
    }

    private var authorAvatar: some View {
        let initial = pr.author.prefix(1).uppercased()
        let hue = Double(abs(pr.author.hashValue) % 360) / 360.0

        return Text(initial)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(Color(hue: hue, saturation: 0.6, brightness: 0.8)))
    }
}
