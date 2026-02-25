import SwiftUI

struct ExplainFlowScreen: View {
    @Bindable var model: RepositoryViewModel

    private enum DetailTab: String, CaseIterable, Identifiable {
        case delta
        case story
        case technical

        var id: String { rawValue }
        var title: String {
            switch self {
            case .delta: return L10n("explain.tab.delta")
            case .story: return L10n("explain.tab.story")
            case .technical: return L10n("explain.tab.technical")
            }
        }
    }

    @State private var splitRatio: CGFloat = 0.64
    @State private var selectedNodeID: String?
    @State private var detailTab: DetailTab = .delta
    @State private var isGuideExpanded: Bool = true

    private var selectedTerm: ExplainGlossaryTerm? {
        if let id = model.explainSelectedTermID {
            return model.explainGlossary.first(where: { $0.id == id })
        }
        return model.explainGlossary.first
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            content
        }
        .padding(.horizontal, 18)
        .padding(.top, 22)
        .padding(.bottom, 12)
        .onAppear {
            model.loadExplainFlow(commitID: model.selectedCommitID, scopeMode: model.explainScopeMode)
        }
        .onChange(of: model.selectedCommitID) { _, commitID in
            model.loadExplainFlow(commitID: commitID, scopeMode: model.explainScopeMode)
            selectedNodeID = nil
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n("explain.title"))
                    .font(.title2.weight(.semibold))
                if let commitID = model.explainSelectedCommitID {
                    Text(L10n("explain.subtitle.commit", String(commitID.prefix(8))))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(L10n("explain.subtitle.placeholder"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Picker("", selection: $model.explainScopeMode) {
                ForEach(ExplainScopeMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 340)
            .onChange(of: model.explainScopeMode) { _, newMode in
                model.setExplainScope(newMode)
                selectedNodeID = nil
            }

            if model.explainAutoContextApplied {
                Text(L10n("explain.autoContext"))
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(DesignSystem.Colors.warning.opacity(0.16))
                    .foregroundStyle(DesignSystem.Colors.warning)
                    .clipShape(Capsule())
            }

            if let graph = model.explainGraph {
                Text(graph.renderBudgetLevel.title)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(DesignSystem.Colors.info.opacity(0.16))
                    .foregroundStyle(DesignSystem.Colors.info)
                    .clipShape(Capsule())

                Text(graph.detailSource.title)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(DesignSystem.Colors.glassSubtle)
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())

                if graph.truncated {
                    Text(L10n("explain.truncated"))
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(DesignSystem.Colors.warning.opacity(0.16))
                        .foregroundStyle(DesignSystem.Colors.warning)
                        .clipShape(Capsule())
                }
            }

            if model.isExplainFlowLoading || model.isExplainAIEnriching {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                model.loadExplainFlow(commitID: model.explainSelectedCommitID ?? model.selectedCommitID, scopeMode: model.explainScopeMode)
            } label: {
                Label(L10n("explain.action.reload"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.explainSelectedCommitID == nil)

            Button {
                model.enrichExplainFlowWithAI()
            } label: {
                Label(L10n("explain.action.ai"), systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(DesignSystem.Colors.ai)
            .disabled(!model.isAIConfigured || model.explainGraph == nil || model.isExplainAIEnriching)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.explainSelectedCommitID == nil {
            placeholder(
                icon: "point.bottomleft.forward.to.point.topright.scurvepath",
                title: L10n("explain.empty.title"),
                message: L10n("explain.empty.message")
            )
        } else if let graph = model.explainGraph, let story = model.explainStory {
            DraggableSplitView(
                axis: .horizontal,
                ratio: $splitRatio,
                minLeading: 520,
                minTrailing: 340
            ) {
                graphPane(graph: graph)
                    .padding(.trailing, 6)
            } trailing: {
                detailPane(graph: graph, story: story)
                    .padding(.leading, 6)
            }
        } else if model.isExplainFlowLoading {
            placeholder(
                icon: "hourglass",
                title: L10n("explain.loading.title"),
                message: L10n("explain.loading.message")
            )
        } else {
            placeholder(
                icon: "exclamationmark.triangle",
                title: L10n("explain.failed.title"),
                message: model.explainLastError ?? L10n("explain.failed.message")
            )
        }
    }

    private func graphPane(graph: ExplainGraph) -> some View {
        GlassCard(spacing: 12) {
            CardHeader(L10n("explain.graph.title"), icon: "point.3.filled.connected.trianglepath.dotted")
            GeometryReader { geo in
                let positions = nodePositions(for: graph.nodes, in: geo.size)
                let highlighted = Set(graph.highlightedNodeIDs)
                ZStack {
                    Canvas { context, _ in
                        for edge in graph.edges {
                            guard let from = positions[edge.from], let to = positions[edge.to] else { continue }
                            var path = Path()
                            path.move(to: from)
                            let control1 = CGPoint(x: from.x + 90, y: from.y)
                            let control2 = CGPoint(x: to.x - 90, y: to.y)
                            path.addCurve(to: to, control1: control1, control2: control2)
                            let edgeHighlighted = highlighted.contains(edge.from) || highlighted.contains(edge.to)
                            let baseColor = edge.inferred ? Color.secondary : DesignSystem.Colors.brandPrimary
                            let opacity = edgeHighlighted ? (edge.inferred ? 0.55 : 0.9) : 0.18
                            context.stroke(
                                path,
                                with: .color(baseColor.opacity(opacity)),
                                style: StrokeStyle(lineWidth: edge.inferred ? 1.2 : 2.0, lineCap: .round, dash: edge.inferred ? [6, 5] : [])
                            )
                        }
                    }

                    ForEach(graph.nodes) { node in
                        let point = positions[node.id] ?? .zero
                        let isHighlighted = highlighted.contains(node.id)
                        let isSelected = selectedNodeID == node.id
                        let nodeWidth: CGFloat = {
                            switch node.kind {
                            case .symbol: return 160
                            case .file: return 200
                            default: return 210
                            }
                        }()
                        Button {
                            selectedNodeID = node.id
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Image(systemName: node.kind.icon)
                                        .font(.system(size: 10, weight: .bold))
                                    Text(node.title)
                                        .font(.system(size: 11, weight: .semibold))
                                        .lineLimit(1)
                                }
                                Text(node.subtitle)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(width: nodeWidth, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                                    .fill(isSelected ? node.kind.color.opacity(0.22) : DesignSystem.Colors.glassSubtle)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                                    .stroke(
                                        isSelected
                                            ? node.kind.color.opacity(0.85)
                                            : (isHighlighted ? node.kind.color.opacity(0.45) : DesignSystem.Colors.glassBorderDark),
                                        lineWidth: 1
                                    )
                            )
                            .opacity(isHighlighted || isSelected ? 1 : 0.56)
                        }
                        .buttonStyle(.plain)
                        .position(point)
                    }
                }
            }
            .frame(minHeight: 420)
        }
    }

    private func detailPane(graph: ExplainGraph, story: ExplainStory) -> some View {
        GlassCard(spacing: 12) {
            flowGuide

            HStack {
                Picker("", selection: $detailTab) {
                    ForEach(DetailTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                if story.generatedByAI {
                    Text(L10n("graph.commit.review.cached"))
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(DesignSystem.Colors.ai.opacity(0.18))
                        .clipShape(Capsule())
                        .foregroundStyle(DesignSystem.Colors.ai)
                }
            }

            if detailTab == .delta {
                deltaPanel()
            } else if detailTab == .story {
                storyPanel(story: story)
            } else {
                technicalPanel(graph: graph)
            }
        }
    }

    private var flowGuide: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "compass.drawing")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.info)
                Text(L10n("explain.guide.title"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button {
                    withAnimation(DesignSystem.Motion.detail) {
                        isGuideExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isGuideExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if isGuideExpanded {
                VStack(alignment: .leading, spacing: 5) {
                    Text("• \(L10n("explain.guide.anchor"))")
                    Text("• \(L10n("explain.guide.operations"))")
                    Text("• \(L10n("explain.guide.files"))")
                    Text("• \(L10n("explain.guide.symbols"))")
                    Text("• \(L10n("explain.guide.risks"))")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(DesignSystem.Colors.glassSubtle)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius))
    }

    private func deltaPanel() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n("explain.delta.title"))
                    .font(.system(size: 14, weight: .bold))
                if let delta = model.explainDelta {
                    deltaSection(title: L10n("explain.delta.added"), values: delta.addedPaths)
                    deltaSection(title: L10n("explain.delta.changed"), values: delta.changedPaths)
                    deltaSection(title: L10n("explain.delta.removed"), values: delta.removedPaths)
                    deltaTextSection(title: L10n("explain.delta.impact"), values: delta.impactNotes)
                    deltaTextSection(title: L10n("explain.delta.risk"), values: delta.riskNotes)
                } else {
                    Text(L10n("explain.delta.none"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func storyPanel(story: ExplainStory) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(story.title)
                    .font(.system(size: 14, weight: .bold))

                Group {
                    if let attributed = try? AttributedString(markdown: story.markdown) {
                        Text(attributed)
                    } else {
                        Text(story.markdown)
                    }
                }
                .font(.system(size: 12))
                .lineSpacing(3)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .environment(\.openURL, OpenURLAction { url in
                    guard url.scheme == "zion-glossary" else { return .systemAction }
                    let id = (url.host ?? url.path).replacingOccurrences(of: "/", with: "")
                    if !id.isEmpty {
                        model.selectExplainTerm(id)
                    }
                    return .handled
                })

                if let term = selectedTerm {
                    glossaryDetail(term)
                } else {
                    Text(L10n("explain.glossary.empty"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func glossaryDetail(_ term: ExplainGlossaryTerm) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.info)
                Text(term.term)
                    .font(.system(size: 12, weight: .bold))
            }

            Text(term.definition)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if !term.evidence.isEmpty {
                ForEach(term.evidence) { evidence in
                    Button {
                        model.openExplainEvidence(evidence)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 10))
                            Text(evidence.filePath)
                                .font(.system(size: 10, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DesignSystem.Colors.glassOverlay)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
                }
            }
        }
        .padding(10)
        .background(DesignSystem.Colors.glassSubtle)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius))
    }

    private func technicalPanel(graph: ExplainGraph) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n("explain.technical.notes"))
                    .font(.system(size: 13, weight: .bold))
                Text(L10n("explain.technical.budget", graph.renderBudgetLevel.title))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(L10n("explain.technical.source", graph.detailSource.title))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(graph.truncated ? L10n("explain.technical.truncated.yes") : L10n("explain.technical.truncated.no"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                ForEach(graph.technicalNotes, id: \.self) { note in
                    Text("• \(note)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Divider()

                Text(L10n("explain.technical.nodes"))
                    .font(.system(size: 13, weight: .bold))
                ForEach(graph.nodes) { node in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(node.title)
                            .font(.system(size: 11, weight: .semibold))
                        Text(node.subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }

                Divider()

                Text(L10n("explain.technical.edges"))
                    .font(.system(size: 13, weight: .bold))
                ForEach(graph.edges) { edge in
                    Text("\(edge.from) → \(edge.to) · \(edge.label)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Divider()
                Text(L10n("explain.technical.confidence"))
                    .font(.system(size: 13, weight: .bold))
                Text(L10n("explain.technical.confidence.exact"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(L10n("explain.technical.confidence.inferred"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func nodePositions(for nodes: [ExplainNode], in size: CGSize) -> [String: CGPoint] {
        var positions: [String: CGPoint] = [:]
        let commitNodes = nodes.filter { $0.kind == .commit }
        let kindNodes = nodes.filter { $0.id.hasPrefix("kind.") }
        let operationNodes = nodes.filter { $0.kind == .operation }
        let fileNodes = nodes.filter { $0.kind == .file }
        let symbolNodes = nodes.filter { $0.kind == .symbol }
        let insightNodes = nodes.filter { $0.kind == .insight }
        let remainingNodes = nodes.filter {
            $0.kind != .commit
            && !$0.id.hasPrefix("kind.")
            && $0.kind != .operation
            && $0.kind != .file
            && $0.kind != .symbol
            && $0.kind != .insight
        }

        if commitNodes.count == 1, let single = commitNodes.first {
            positions[single.id] = CGPoint(x: size.width * 0.24, y: size.height * 0.5)
        } else if !commitNodes.isEmpty {
            let count = commitNodes.count
            let spacing = max(72.0, (size.height - 120) / CGFloat(max(count, 1)))
            let startY = (size.height - (CGFloat(count - 1) * spacing)) / 2
            for (index, node) in commitNodes.enumerated() {
                let x = size.width * 0.2
                let y = startY + CGFloat(index) * spacing
                positions[node.id] = CGPoint(x: x, y: y)
            }
        }

        func placeColumn(_ columnNodes: [ExplainNode], x: CGFloat) {
            guard !columnNodes.isEmpty else { return }
            let count = columnNodes.count
            let spacing = max(70.0, (size.height - 80) / CGFloat(max(count, 1)))
            let startY = (size.height - (CGFloat(count - 1) * spacing)) / 2
            for (index, node) in columnNodes.enumerated() {
                positions[node.id] = CGPoint(
                    x: size.width * x,
                    y: startY + CGFloat(index) * spacing
                )
            }
        }

        placeColumn(kindNodes, x: 0.48)
        placeColumn(operationNodes, x: 0.62)
        placeColumn(fileNodes, x: 0.74)
        placeColumn(symbolNodes, x: 0.86)
        placeColumn(insightNodes, x: 0.94)
        placeColumn(remainingNodes, x: 0.68)
        return positions
    }

    private func deltaSection(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
            if values.isEmpty {
                Text(L10n("explain.delta.none"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(values.prefix(8), id: \.self) { value in
                    Text(value)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private func deltaTextSection(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
            if values.isEmpty {
                Text(L10n("explain.delta.none"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(values, id: \.self) { value in
                    Text("• \(value)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func placeholder(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 15, weight: .bold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 50)
    }
}
