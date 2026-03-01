import SwiftUI

struct PRReviewSubmitSheet: View {
    @Bindable var model: RepositoryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var reviewBody: String = ""
    @State private var reviewEvent: PRReviewEvent = .comment
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "checkmark.message")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.codeReview)
                Text(L10n("pr.review.submit"))
                    .font(.headline)
                Spacer()
            }
            .padding(16)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                // Review state picker
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.micro) {
                    Picker(L10n("tag.detail.type"), selection: $reviewEvent) {
                        ForEach(PRReviewEvent.allCases) { event in
                            Label(event.label, systemImage: event.icon).tag(event)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Review body
                TextEditor(text: $reviewBody)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius)
                            .stroke(DesignSystem.Colors.glassBorderDark)
                    )

                // Pending draft comments count
                if !model.pendingReviewComments.isEmpty {
                    HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                        Image(systemName: "text.bubble")
                            .foregroundStyle(DesignSystem.Colors.info)
                        Text(L10n("pr.review.comments.count", model.pendingReviewComments.count))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                // Error
                if let error = errorMessage {
                    HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(DesignSystem.Colors.warning)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(DesignSystem.Colors.warning.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius))
                }
            }
            .padding(16)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button(L10n("pr.comment.cancel")) { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button {
                    submitReview()
                } label: {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(L10n("pr.review.submit"), systemImage: reviewEvent.icon)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(tintForEvent)
                .disabled(isSubmitting)
            }
            .padding(16)
        }
        .frame(width: 500, height: 420)
    }

    private var tintForEvent: Color {
        switch reviewEvent {
        case .approve: return DesignSystem.Colors.success
        case .requestChanges: return DesignSystem.Colors.destructive
        case .comment: return DesignSystem.Colors.actionPrimary
        }
    }

    private func submitReview() {
        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                try await model.submitPRReview(body: reviewBody, event: reviewEvent)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}
