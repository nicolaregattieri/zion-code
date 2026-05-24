// MentionsCostPreview.swift
// Inline preview below the composer: shows estimated bytes + token count for @mentions.
// Updates with a 300 ms debounce via MentionResolver.dryRun (no I/O).
//
// Phase 12, Task 8.

import SwiftUI

// MARK: - MentionsCostPreview

struct MentionsCostPreview: View {

    let message: String
    let resolver: MentionResolver

    @State private var estimatedBytes: Int = 0
    @State private var mentionCount: Int = 0
    @State private var dryRunTask: Task<Void, Never>?

    var body: some View {
        Group {
            if mentionCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "paperclip")
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(DesignSystem.Colors.brandPrimary)
                    Text(previewText)
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, DesignSystem.Spacing.cardPadding)
                .padding(.vertical, DesignSystem.Spacing.micro)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: mentionCount > 0)
        .onChange(of: message) { _, newMessage in
            debouncedDryRun(newMessage)
        }
        .onAppear {
            debouncedDryRun(message)
        }
        .onDisappear {
            dryRunTask?.cancel()
        }
    }

    // MARK: - Private

    private var previewText: String {
        let tokensEstimate = max(1, estimatedBytes / 4)
        let bytesStr = formatBytes(estimatedBytes)
        return L10n("chat.mentions.preview", "\(mentionCount)", bytesStr, "~\(formatTokens(tokensEstimate))")
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens < 1000 { return "\(tokens)" }
        return String(format: "%.1fk", Double(tokens) / 1000)
    }

    private func debouncedDryRun(_ message: String) {
        dryRunTask?.cancel()
        // Quick check: no '@' means no mentions — reset immediately without async
        guard message.contains("@") else {
            estimatedBytes = 0
            mentionCount = 0
            return
        }
        dryRunTask = Task { [resolver] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                return // cancelled
            }
            guard !Task.isCancelled else { return }
            let result = await resolver.dryRun(message: message)
            await MainActor.run {
                self.estimatedBytes = result.estimatedBytes
                self.mentionCount = result.mentionCount
            }
        }
    }
}
