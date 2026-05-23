import SwiftUI

// MARK: - AgentStepIndicator
// Small capsule shown in the conversation card header when AgentRuntime.isLoopActive is true.
// Displays: spinning sparkle + "Step N/M" + provider name.
// Shows nothing when the loop is inactive.

struct AgentStepIndicator: View {

    // MARK: - TODO(T11): L10n — key: chat.agent.step.label  (format: "Step %d/%d")

    @Bindable var agentRuntime: AgentRuntime
    @AppStorage("chat.agent.maxSteps") private var maxSteps: Int = 25

    @State private var spinAngle: Double = 0

    var body: some View {
        if agentRuntime.isLoopActive {
            HStack(spacing: DesignSystem.Spacing.compact) {
                Image(systemName: "sparkles")
                    .font(DesignSystem.Typography.monoLabelBold)
                    .foregroundStyle(DesignSystem.Colors.ai)
                    .rotationEffect(.degrees(spinAngle))
                    .onAppear {
                        withAnimation(
                            .linear(duration: 2.0)
                            .repeatForever(autoreverses: false)
                        ) {
                            spinAngle = 360
                        }
                    }

                Text("Step \(agentRuntime.currentStepIndex)/\(maxSteps)") // MARK: - TODO(T11): L10n — key: chat.agent.step.label
                    .font(DesignSystem.Typography.monoLabelBold)

                if let provider = agentRuntime.currentProviderResolved {
                    Text(provider.label)
                        .font(DesignSystem.Typography.monoLabelBold)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.standard)
            .padding(.vertical, DesignSystem.Spacing.compact / 2)
            .background(DesignSystem.Colors.glassSubtle)
            .clipShape(Capsule())
        }
    }
}
