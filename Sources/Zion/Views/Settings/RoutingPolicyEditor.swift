import SwiftUI

// MARK: - TODO(T10): L10n — all string literals here need L10n() once keys are added in T10

struct RoutingPolicyEditor: View {
    @State private var policy: RoutingPolicy = RoutingPolicy.load()

    /// Lanes to display — skip transcription (audio-only).
    private var editableLanes: [AITaskLane] {
        AITaskLane.allCases.filter { $0 != .transcription }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            priorityHint
            ForEach(editableLanes) { lane in
                laneRow(lane: lane)
                if lane != editableLanes.last {
                    Divider()
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// One-time hint at the top explaining priority direction.
    private var priorityHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.left.and.right")
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            Text("Highest priority on the left — Zion tries each provider in order on quota / network errors.")
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
    }

    @ViewBuilder
    private func laneRow(lane: AITaskLane) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lane.label)
                .font(DesignSystem.Typography.labelBold)

            // Use a wrapping HStack via VStack-of-rows so capsules don't crush.
            FlowLayout(spacing: 8, maxItemsPerRow: .max) {
                let chain = policy.chains[lane.rawValue] ?? []
                ForEach(Array(chain.enumerated()), id: \.offset) { index, rawProvider in
                    capsule(lane: lane, rawProvider: rawProvider, index: index, chainCount: chain.count)
                }
                addProviderMenu(lane: lane)
            }
        }
    }

    @ViewBuilder
    private func capsule(lane: AITaskLane, rawProvider: String, index: Int, chainCount: Int) -> some View {
        let provider = AIProvider(rawValue: rawProvider)
        let shortLabel = provider.map(Self.shortName(for:)) ?? rawProvider
        let fullLabel = provider?.label ?? rawProvider

        HStack(spacing: 6) {
            Text("\(index + 1)")
                .font(DesignSystem.Typography.metaSemibold)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .frame(minWidth: 12, alignment: .leading)

            if index > 0 {
                Button {
                    moveProvider(lane: lane, from: index, to: index - 1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Move left")
            }

            Text(shortLabel)
                .font(DesignSystem.Typography.metaSemibold)
                .lineLimit(1)
                .fixedSize()
                .help(fullLabel)

            if index < chainCount - 1 {
                Button {
                    moveProvider(lane: lane, from: index, to: index + 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Move right")
            }

            Button {
                removeProvider(lane: lane, at: index)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(DesignSystem.Colors.actionPrimary.opacity(0.12))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func addProviderMenu(lane: AITaskLane) -> some View {
        let chain = policy.chains[lane.rawValue] ?? []
        let available = AIProvider.allCases.filter {
            !chain.contains($0.rawValue) && $0 != .none && $0 != .auto
        }

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
            .help("Add provider")
        }
    }

    /// Short display names so capsules fit on one line.
    private static func shortName(for provider: AIProvider) -> String {
        switch provider {
        case .auto: return "Auto"
        case .anthropic: return "Claude API"
        case .openai: return "OpenAI"
        case .gemini: return "Gemini"
        case .local: return "Local"
        case .claudeCLI: return "Claude CLI"
        case .codexCLI: return "Codex CLI"
        case .none: return "—"
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

// FlowLayout reuses the shared implementation at Sources/Zion/Views/Components/FlowLayout.swift
