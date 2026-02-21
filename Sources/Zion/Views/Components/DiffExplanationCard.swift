import SwiftUI

struct DiffExplanationCard: View {
    let explanation: DiffExplanation
    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with severity badge
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.purple)
                Text(L10n("diff.explanation.title"))
                    .font(.system(size: 12, weight: .bold))
                Spacer()

                // Severity badge
                Text(explanation.severity.label)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(explanation.severity.color.opacity(0.15))
                    .foregroundStyle(explanation.severity.color)
                    .clipShape(Capsule())

                if let onDismiss {
                    Button { onDismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Intent section
            VStack(alignment: .leading, spacing: 4) {
                Label(L10n("diff.explanation.intent"), systemImage: "target")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(explanation.intent)
                    .font(.system(size: 11))
                    .textSelection(.enabled)
            }

            // Risks section
            VStack(alignment: .leading, spacing: 4) {
                Label(L10n("diff.explanation.risks"), systemImage: "exclamationmark.shield")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(explanation.severity.color)
                Text(explanation.risks)
                    .font(.system(size: 11))
                    .textSelection(.enabled)
            }

            // Narrative section
            VStack(alignment: .leading, spacing: 4) {
                Label(L10n("diff.explanation.narrative"), systemImage: "text.book.closed")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(explanation.narrative)
                    .font(.system(size: 11))
                    .textSelection(.enabled)
            }

            // Copy button
            HStack {
                Spacer()
                Button {
                    let text = """
                    Intent: \(explanation.intent)
                    Risks: \(explanation.risks)
                    Narrative: \(explanation.narrative)
                    """
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label(L10n("diff.explanation.copy"), systemImage: "doc.on.doc")
                        .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DesignSystem.Colors.glassSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DesignSystem.Colors.glassHover, lineWidth: 1)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct DiffExplanationShimmer: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.purple)
                Text(L10n("diff.explanation.loading"))
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                ProgressView()
                    .controlSize(.small)
            }

            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(isAnimating ? 0.08 : 0.03))
                    .frame(height: 12)
                    .frame(maxWidth: i == 2 ? 200 : .infinity)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DesignSystem.Colors.glassSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DesignSystem.Colors.glassHover, lineWidth: 1)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}
