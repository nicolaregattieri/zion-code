import SwiftUI

// MARK: - ApplyAllState

enum ApplyAllState: Equatable {
    case ready(Int)
    case applying(Int, Int)
    case stopped(at: Int)
    case done(Int)
}

// MARK: - ApplyAllButton

struct ApplyAllButton: View {
    var blocks: [EditBlock]
    var isStreaming: Bool
    var state: ApplyAllState
    var onTap: () -> Void

    private var isDisabled: Bool {
        guard !isStreaming else { return true }
        if case .applying = state { return true }
        return false
    }

    var body: some View {
        Button {
            tap()
        } label: {
            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                if case .applying = state {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(DesignSystem.Colors.ai)
                }
                Text(buttonLabel)
                    .font(DesignSystem.Typography.bodySemibold)
                    .foregroundStyle(labelColor)
            }
            .padding(.horizontal, DesignSystem.Spacing.standard)
            .padding(.vertical, DesignSystem.Spacing.compact)
            .background(backgroundTint)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    // MARK: - Label helpers

    private var buttonLabel: String {
        switch state {
        case .ready(let count):
            // MARK: - TODO(T10): L10n
            return "Apply all (\(count))"
        case .applying(let done, let total):
            // MARK: - TODO(T10): L10n
            return "Applying \(done)/\(total)\u{2026}"
        case .stopped(let at):
            // MARK: - TODO(T10): L10n
            return "Stopped at block \(at)"
        case .done(let count):
            // MARK: - TODO(T10): L10n
            return "\(count) applied"
        }
    }

    private var labelColor: Color {
        switch state {
        case .ready:   return isDisabled ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.success
        case .applying: return DesignSystem.Colors.ai
        case .stopped: return DesignSystem.Colors.error
        case .done:    return DesignSystem.Colors.success
        }
    }

    private var backgroundTint: Color {
        switch state {
        case .ready:   return isDisabled ? DesignSystem.Colors.glassSubtle : DesignSystem.Colors.success.opacity(0.15)
        case .applying: return DesignSystem.Colors.ai.opacity(0.15)
        case .stopped: return DesignSystem.Colors.error.opacity(0.12)
        case .done:    return DesignSystem.Colors.success.opacity(0.15)
        }
    }

    // MARK: - Action Helper (testable)

    internal func tap() {
        guard !isDisabled else { return }
        onTap()
    }
}
