import SwiftUI

// MARK: - ProviderSwitchBanner

struct ProviderSwitchBanner: View {

    let event: ProviderSwitchEvent
    var onDismiss: () -> Void = {}

    @State private var dismissTask: Task<Void, Never>?

    // MARK: - Body

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.compact) {
            Image(systemName: "arrow.triangle.swap")
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            // MARK: - TODO(T10): L10n
            Text("\(event.from.rawValue) → \(event.to.rawValue)")
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            if !event.reason.isEmpty {
                Text("·")
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                Text(event.reason)
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                dismissTapped()
            } label: {
                Image(systemName: "xmark")
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DesignSystem.Spacing.compact)
        .padding(.vertical, DesignSystem.Spacing.micro)
        .background(DesignSystem.Colors.glassHover)
        .clipShape(Capsule())
        .onAppear {
            scheduleDismiss()
        }
        .onDisappear {
            dismissTask?.cancel()
        }
    }

    // MARK: - Internal Helpers (testable without view introspection)

    internal func dismissTapped() {
        dismissTask?.cancel()
        onDismiss()
    }

    // MARK: - Private

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled {
                onDismiss()
            }
        }
    }
}
