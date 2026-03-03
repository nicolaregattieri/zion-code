import SwiftUI

/// Floating glassmorphism pill that appears above the terminal when voice input is active.
/// Shows animated waveform bars, live transcript, and a duration timer.
struct VoiceActivePill: View {
    var speechService: SpeechRecognitionService
    var onStop: () -> Void

    @State private var barLevels: [CGFloat] = Array(repeating: 0.2, count: 5)
    @State private var elapsedSeconds: Int = 0
    @State private var timerTask: Task<Void, Never>?
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        Button {
            onStop()
        } label: {
            HStack(spacing: DesignSystem.Spacing.standard) {
                // Pulsing red dot
                Circle()
                    .fill(DesignSystem.Colors.error)
                    .frame(width: 8, height: 8)
                    .shadow(color: DesignSystem.Colors.error.opacity(0.6), radius: 4)

                // Animated waveform bars
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(DesignSystem.Colors.error.opacity(0.8))
                            .frame(width: 3, height: barLevels[i] * 16)
                    }
                }
                .frame(height: 16)

                // Live transcript (truncated)
                if !speechService.currentTranscript.isEmpty {
                    Text(speechService.currentTranscript)
                        .font(DesignSystem.Typography.bodySmall)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .frame(maxWidth: 280, alignment: .leading)
                }

                // Duration
                Text(formattedDuration)
                    .font(DesignSystem.Typography.monoLabel)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, DesignSystem.Spacing.cardPadding)
            .padding(.vertical, DesignSystem.Spacing.compact)
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.containerCornerRadius)
                    .stroke(DesignSystem.Colors.glassBorderDark, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.containerCornerRadius))
            .shadow(color: DesignSystem.Colors.shadowDark, radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .onAppear { startAnimations() }
        .onDisappear { stopAnimations() }
    }

    // MARK: - Timer

    private var formattedDuration: String {
        let m = elapsedSeconds / 60
        let s = elapsedSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func startAnimations() {
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                elapsedSeconds += 1
            }
        }

        animationTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                withAnimation(DesignSystem.Motion.graph) {
                    for i in 0..<5 {
                        barLevels[i] = CGFloat.random(in: 0.15...1.0)
                    }
                }
            }
        }
    }

    private func stopAnimations() {
        timerTask?.cancel()
        timerTask = nil
        animationTask?.cancel()
        animationTask = nil
        elapsedSeconds = 0
    }
}
