import SwiftUI

struct PRInboxCard: View {
    var model: RepositoryViewModel
    @State private var isExpanded: Bool = true

    var body: some View {
        if !model.prReviewQueue.isEmpty {
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
}
