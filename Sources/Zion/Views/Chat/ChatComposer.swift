import SwiftUI

// MARK: - ChatComposer

struct ChatComposer: View {

    @Bindable var chat: ChatService
    @Binding var text: String

    let onSend: () -> Void
    let onStop: () -> Void
    let onNewChat: () -> Void

    @AppStorage(UserDefaultsKeys.AI.provider) private var selectedProviderRaw: String = AIProvider.none.rawValue

    private var selectedProvider: Binding<AIProvider> {
        Binding(
            get: { AIProvider(rawValue: selectedProviderRaw) ?? .none },
            set: { selectedProviderRaw = $0.rawValue }
        )
    }

    private var canSend: Bool {
        !chat.isStreaming && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.standard) {
            providerMenu
            inputField
            actionButtons
        }
        .padding(.horizontal, DesignSystem.Spacing.cardPadding)
        .padding(.vertical, DesignSystem.Spacing.standard)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous)
                .fill(DesignSystem.Colors.glassBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous)
                .stroke(DesignSystem.Colors.glassBorder, lineWidth: 1)
        )
    }

    // MARK: - Sub-views

    private var providerMenu: some View {
        Menu {
            ForEach(AIProviderSupport.configurableProviders) { provider in
                Button {
                    selectedProviderRaw = provider.rawValue
                } label: {
                    HStack {
                        Text(provider.label)
                        if selectedProvider.wrappedValue == provider {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                Image(systemName: "cpu")
                    .font(DesignSystem.Typography.label)
                Text(selectedProvider.wrappedValue == .none ? L10n("settings.ai.provider.local") : selectedProvider.wrappedValue.label)
                    .font(DesignSystem.Typography.labelMedium)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(DesignSystem.Typography.label)
            }
            .foregroundStyle(DesignSystem.Colors.textSecondary)
            .padding(.horizontal, DesignSystem.Spacing.compact)
            .padding(.vertical, DesignSystem.Spacing.micro)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous)
                    .fill(DesignSystem.Colors.glassHover)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous)
                    .stroke(DesignSystem.Colors.glassStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private var inputField: some View {
        TextField(L10n("chat.composer.hint"), text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .labelsHidden()
            .font(DesignSystem.Typography.body)
            .lineLimit(1...5)
            .padding(.horizontal, DesignSystem.Spacing.standard)
            .padding(.vertical, DesignSystem.Spacing.compact)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                    .fill(DesignSystem.Colors.glassHover)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                    .stroke(DesignSystem.Colors.glassStroke, lineWidth: 1)
            )
            .onSubmit {
                if canSend { onSend() }
            }
    }

    private var actionButtons: some View {
        HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
            if chat.isStreaming {
                stopButton
            } else {
                sendButton
            }
            newChatButton
        }
    }

    private var sendButton: some View {
        Button {
            onSend()
        } label: {
            Image(systemName: "paperplane.fill")
                .font(DesignSystem.Typography.bodySmall)
                .frame(width: 28, height: 28)
                .foregroundStyle(canSend ? DesignSystem.Colors.primary : DesignSystem.Colors.textTertiary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .help(L10n("chat.composer.send"))
        .keyboardShortcut(.return, modifiers: [])
    }

    private var stopButton: some View {
        Button {
            onStop()
        } label: {
            Image(systemName: "stop.fill")
                .font(DesignSystem.Typography.bodySmall)
                .frame(width: 28, height: 28)
                .foregroundStyle(DesignSystem.Colors.destructive)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n("chat.composer.stop"))
    }

    private var newChatButton: some View {
        Button {
            onNewChat()
        } label: {
            Image(systemName: "trash")
                .font(DesignSystem.Typography.bodySmall)
                .frame(width: 28, height: 28)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n("chat.composer.newChat"))
    }
}
