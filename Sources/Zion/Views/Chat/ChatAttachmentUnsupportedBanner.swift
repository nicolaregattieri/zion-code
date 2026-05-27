import SwiftUI

/// Phase 4 — inline banner rendered next to the assistant turn when an
/// attached image is dropped on the floor because the active model is
/// text-only or the attachment MIME is not in
/// `Constants.Attachments.acceptedMIMEs`. The user message still sends
/// (as plain text); this banner explains why the image was not forwarded.
struct ChatAttachmentUnsupportedBannerView: View {

    enum Reason {
        case textOnlyModel
        case unsupportedMIME(String)

        var labelKey: String {
            switch self {
            case .textOnlyModel: return "attachment.unsupported.textOnly"
            case .unsupportedMIME: return "attachment.unsupported.mime"
            }
        }

        var detail: String {
            switch self {
            case .textOnlyModel: return ""
            case .unsupportedMIME(let mime): return mime
            }
        }
    }

    let reason: Reason

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.iconTextGap) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n(reason.labelKey))
                    .font(DesignSystem.Typography.bodySemibold)
                    .foregroundStyle(DesignSystem.Colors.warning)
                if !reason.detail.isEmpty {
                    Text(reason.detail)
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignSystem.Spacing.standard)
        .padding(.vertical, DesignSystem.Spacing.compact)
        .background(DesignSystem.Colors.warning.opacity(DesignSystem.Opacity.dim))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous))
    }
}
