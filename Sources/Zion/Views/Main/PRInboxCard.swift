import SwiftUI

struct PRInboxCard: View {
    var model: RepositoryViewModel
    @State private var isExpanded: Bool = true

    var body: some View {
        if model.hasGitHubRemote {
            if model.prReviewQueue.isEmpty {
                emptyState
            } else {
                prList
            }
        }
    }

    private var emptyState: some View {
        GlassCard(spacing: 10) {
            CardHeader(L10n("pr.inbox.title"), icon: "arrow.triangle.pull")

            VStack(spacing: 6) {
                Image(systemName: "tray")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                Text(L10n("pr.inbox.empty"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(L10n("pr.inbox.setup.hint"))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .padding(.horizontal, 10)
    }

    private var prList: some View {
        GlassCard(spacing: 10) {
            CardHeader(L10n("pr.inbox.title"), icon: "arrow.triangle.pull") {
                HStack(spacing: 6) {
                    Text("\(model.prReviewQueue.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.indigo.opacity(0.7)))

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
        .padding(.horizontal, 10)
    }
}
