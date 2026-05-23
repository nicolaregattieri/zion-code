import SwiftUI

// MARK: - TODO(T10): L10n — all string literals here need L10n() once keys are added in T10

struct RoutingPolicyEditor: View {
    @State private var policy: RoutingPolicy = RoutingPolicy.load()

    /// Lanes to display — skip transcription (audio-only).
    private var editableLanes: [AITaskLane] {
        AITaskLane.allCases.filter { $0 != .transcription }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(editableLanes) { lane in
                laneRow(lane: lane)
                if lane != editableLanes.last {
                    Divider()
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func laneRow(lane: AITaskLane) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(lane.label)
                .font(DesignSystem.Typography.labelBold)

            HStack(spacing: 6) {
                let chain = policy.chains[lane.rawValue] ?? []
                ForEach(Array(chain.enumerated()), id: \.offset) { index, rawProvider in
                    capsule(lane: lane, rawProvider: rawProvider, index: index, chainCount: chain.count)
                }

                addProviderMenu(lane: lane)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func capsule(lane: AITaskLane, rawProvider: String, index: Int, chainCount: Int) -> some View {
        let providerLabel = AIProvider(rawValue: rawProvider)?.label ?? rawProvider

        HStack(spacing: 4) {
            // Move up
            if index > 0 {
                Button {
                    moveProvider(lane: lane, from: index, to: index - 1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Move left") // MARK: - TODO(T10): L10n
            }

            Text(providerLabel)
                .font(DesignSystem.Typography.metaSemibold)

            // Move down
            if index < chainCount - 1 {
                Button {
                    moveProvider(lane: lane, from: index, to: index + 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Move right") // MARK: - TODO(T10): L10n
            }

            // Remove
            Button {
                removeProvider(lane: lane, at: index)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove") // MARK: - TODO(T10): L10n
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(DesignSystem.Colors.actionPrimary.opacity(0.12))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func addProviderMenu(lane: AITaskLane) -> some View {
        let chain = policy.chains[lane.rawValue] ?? []
        let available = AIProvider.allCases.filter { !chain.contains($0.rawValue) }

        if !available.isEmpty {
            Menu {
                ForEach(available) { provider in
                    Button(provider.label) {
                        appendProvider(provider, to: lane)
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(6)
                    .background(DesignSystem.Colors.glassSubtle)
                    .clipShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    // MARK: - Mutation helpers

    private func appendProvider(_ provider: AIProvider, to lane: AITaskLane) {
        var chain = policy.chains[lane.rawValue] ?? []
        guard !chain.contains(provider.rawValue) else { return }
        chain.append(provider.rawValue)
        policy.chains[lane.rawValue] = chain
        policy.save()
    }

    private func removeProvider(lane: AITaskLane, at index: Int) {
        var chain = policy.chains[lane.rawValue] ?? []
        guard chain.indices.contains(index) else { return }
        chain.remove(at: index)
        policy.chains[lane.rawValue] = chain
        policy.save()
    }

    private func moveProvider(lane: AITaskLane, from source: Int, to dest: Int) {
        var chain = policy.chains[lane.rawValue] ?? []
        guard chain.indices.contains(source), chain.indices.contains(dest) else { return }
        chain.swapAt(source, dest)
        policy.chains[lane.rawValue] = chain
        policy.save()
    }
}
