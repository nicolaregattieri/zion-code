import SwiftUI

struct CommitRowView: View {
    let commit: Commit
    let isSelected: Bool
    let isSearchMatch: Bool
    let searchQuery: String
    let laneCount: Int
    let currentBranch: String
    let isAIConfigured: Bool
    let isReviewingThisCommit: Bool
    let onCheckout: (String) -> Void
    let onReviewCommit: (String) -> Void
    let onSelect: () -> Void
    let contextMenu: AnyView
    let branchContextMenu: (String) -> AnyView
    let tagContextMenu: (String) -> AnyView
    let remotes: [String]
    var bisectRole: BisectCommitRole = .none
    var avatarImage: NSImage? = nil
    
    @State private var isHovered = false
    @State private var decorationOverflow: Int = 0
    @State private var showOverflowPopover = false
    
    private let rowHeight: CGFloat = 102
    private let cardHeight: CGFloat = 86

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    var body: some View {
        HStack(spacing: 0) {
            graphColumn
            cardContent
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: rowHeight)
        .clipped()
    }

    private var graphColumn: some View {
        LaneGraphView(
            commit: commit,
            laneCount: laneCount,
            isSelected: isSelected,
            isHead: commit.decorations.contains(where: { $0.contains("HEAD") }),
            height: rowHeight
        )
        .onTapGesture { onSelect() }
    }

    private var laneColor: Color {
        DesignSystem.Colors.laneColor(forKey: commit.nodeColorKey)
    }

    private var cardContent: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius, style: .continuous)
                .fill(cardBackground)
                .frame(height: cardHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius, style: .continuous)
                        .stroke(cardStroke, lineWidth: 1.5)
                )
                .shadow(color: isSelected ? DesignSystem.Colors.hoverAccent : DesignSystem.Colors.shadowLight, radius: isSelected ? 8 : 4, y: 2)

            // Lane color left stripe
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.microCornerRadius)
                    .fill(laneColor)
                    .frame(width: 3, height: cardHeight - 16)
                    .padding(.leading, 4)
                Spacer()
            }
            .frame(height: cardHeight)

            VStack(alignment: .leading, spacing: 6) {
                Text(commit.subject)
                    .font(DesignSystem.Typography.sectionTitle)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                
                metadataRow
                decorationRow
            }
            .padding(.horizontal, 16)
            .frame(height: cardHeight)

            if isAIConfigured {
                HStack {
                    Spacer()
                    Button {
                        onSelect()
                        onReviewCommit(commit.id)
                    } label: {
                        Group {
                            if isReviewingThisCommit {
                                ProgressView()
                                    .controlSize(.mini)
                                    .frame(width: 12, height: 12)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(DesignSystem.Typography.labelBold)
                            }
                        }
                        .foregroundStyle(DesignSystem.Colors.ai)
                        .padding(6)
                        .background(DesignSystem.Colors.glassSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius)
                                .stroke(DesignSystem.Colors.glassBorderDark, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .cursorArrow()
                    .disabled(isReviewingThisCommit)
                    .help(L10n("graph.commit.review"))
                    .accessibilityLabel(L10n("graph.commit.review"))
                    .padding(.top, 6)
                    .padding(.trailing, 8)
                }
                .frame(height: cardHeight, alignment: .topTrailing)
            }

            if bisectRole == .culprit {
                HStack {
                    Spacer()
                    Text(L10n("bisect.badge.culprit"))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(DesignSystem.Colors.destructive)
                        .clipShape(Capsule())
                        .padding(.bottom, 6)
                        .padding(.trailing, 8)
                }
                .frame(height: cardHeight, alignment: .bottomTrailing)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius))
        .scaleEffect(isHovered && !isSelected ? 1.015 : 1.0)
        .shadow(color: isHovered && !isSelected ? DesignSystem.Colors.selectionBackground : .clear, radius: 8, y: 2)
        .animation(DesignSystem.Motion.springInteractive, value: isHovered)
        .animation(DesignSystem.Motion.springInteractive, value: isSelected)
        .onHover { hovering in isHovered = hovering }
        .onTapGesture { onSelect() }
        .opacity(bisectRole == .outsideRange ? DesignSystem.Opacity.dim : DesignSystem.Opacity.full)
        .contextMenu { contextMenu }
        .padding(.trailing, 16)
    }

    private var cardBackground: Color {
        // Bisect roles blend with selection instead of being overridden
        if isSelected {
            switch bisectRole {
            case .currentTest: return DesignSystem.Colors.info.opacity(0.2)
            case .markedGood: return DesignSystem.Colors.success.opacity(0.2)
            case .markedBad, .culprit: return DesignSystem.Colors.destructive.opacity(0.2)
            case .none, .outsideRange: return DesignSystem.Colors.selectionBackground
            }
        }
        switch bisectRole {
        case .currentTest: return DesignSystem.Colors.statusBlueBg
        case .markedGood: return DesignSystem.Colors.statusGreenBg
        case .markedBad, .culprit: return DesignSystem.Colors.destructiveBg
        case .none, .outsideRange: break
        }
        if isSearchMatch { return DesignSystem.Colors.statusYellowBg }
        if isHovered { return DesignSystem.Colors.glassHover }
        return laneColor.opacity(0.06)
    }

    private var cardStroke: Color {
        if isSelected { return DesignSystem.Colors.selectionBorder }
        switch bisectRole {
        case .currentTest: return DesignSystem.Colors.info.opacity(DesignSystem.Opacity.muted)
        case .markedGood: return DesignSystem.Colors.success.opacity(DesignSystem.Opacity.muted)
        case .markedBad, .culprit: return DesignSystem.Colors.destructive.opacity(DesignSystem.Opacity.muted)
        case .none, .outsideRange: break
        }
        if isSearchMatch { return DesignSystem.Colors.searchHighlight.opacity(0.5) }
        if isHovered { return DesignSystem.Colors.hoverAccent }
        return laneColor.opacity(0.15)
    }

    private var metadataRow: some View {
        HStack(spacing: DesignSystem.Spacing.toolbarItemGap) {
            Text(commit.shortHash)
                .font(DesignSystem.Typography.monoLabelBold)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(DesignSystem.Colors.selectionBackground)
                .clipShape(Capsule())
                .foregroundStyle(Color.accentColor)

            HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                if let avatar = avatarImage {
                    Image(nsImage: avatar)
                        .resizable()
                        .frame(width: 18, height: 18)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "person.fill").font(DesignSystem.Typography.meta)
                }
                Text(commit.author)
            }
            .font(DesignSystem.Typography.bodyMedium)
            .foregroundStyle(.secondary)

            HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                Image(systemName: "calendar").font(DesignSystem.Typography.meta)
                Text(Self.dateFormatter.string(from: commit.date))
            }
            .font(DesignSystem.Typography.monoLabel)
            .foregroundStyle(DesignSystem.Colors.textTertiary)

            if let ins = commit.insertions, let del = commit.deletions, (ins > 0 || del > 0) {
                HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                    if ins > 0 {
                        Text("+\(ins)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.diffAddition)
                    }
                    if del > 0 {
                        Text("-\(del)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.diffDeletion)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(DesignSystem.Colors.glassSubtle)
                .clipShape(Capsule())
            }
        }
    }

    private var sortedDecorations: [String] {
        commit.decorations.sorted { a, b in
            decorationPriority(a) < decorationPriority(b)
        }
    }

    private func decorationPriority(_ decoration: String) -> Int {
        let trimmed = decoration.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("HEAD -> ") { return 0 }
        if trimmed == currentBranch { return 1 }
        if trimmed.hasPrefix("tag: ") { return 3 }
        for remote in remotes {
            if trimmed.hasPrefix("\(remote)/") { return 4 }
        }
        return 2 // local branches
    }

    private var decorationRow: some View {
        Group {
            if !commit.decorations.isEmpty {
                TruncatingHStack(spacing: DesignSystem.Spacing.toolbarItemGap, overflowCount: $decorationOverflow) {
                    ForEach(sortedDecorations, id: \.self) { decoration in
                        DecorationPill(
                            decoration: decoration,
                            currentBranch: currentBranch,
                            highlightSearchQuery: searchQuery,
                            onCheckout: { branch in
                                onCheckout(branch)
                            },
                            branchContextMenu: branchContextMenu,
                            tagContextMenu: tagContextMenu,
                            remotes: remotes
                        )
                    }
                    overflowPill
                }
            }
        }
    }

    private var overflowPill: some View {
        Button {
            showOverflowPopover = true
        } label: {
            HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                Image(systemName: "ellipsis")
                    .font(DesignSystem.Typography.micro)
                Text("+\(decorationOverflow)")
                    .font(DesignSystem.Typography.monoLabelBold)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(DesignSystem.Colors.glassSubtle))
            .foregroundStyle(.secondary)
            .overlay(Capsule().strokeBorder(DesignSystem.Colors.glassBorderDark, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(L10n("graph.decoration.overflow", decorationOverflow))
        .popover(isPresented: $showOverflowPopover, arrowEdge: .bottom) {
            overflowPopoverContent
        }
    }

    private var overflowPopoverContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(sortedDecorations, id: \.self) { decoration in
                DecorationPill(
                    decoration: decoration,
                    currentBranch: currentBranch,
                    highlightSearchQuery: searchQuery,
                    onCheckout: { branch in
                        showOverflowPopover = false
                        onCheckout(branch)
                    },
                    branchContextMenu: branchContextMenu,
                    tagContextMenu: tagContextMenu,
                    remotes: remotes
                )
            }
        }
        .padding(12)
        .frame(maxWidth: 320)
    }
}
