import SwiftUI

struct CommitRowView: View {
    let commit: Commit
    let isSelected: Bool
    let isSearchMatch: Bool
    let searchQuery: String
    let laneCount: Int
    let currentBranch: String
    let onCheckout: (String) -> Void
    let onSelect: () -> Void
    let contextMenu: AnyView
    let branchContextMenu: (String) -> AnyView
    let tagContextMenu: (String) -> AnyView
    let remotes: [String]
    
    @State private var isHovered = false
    
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
        }
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

    private var cardContent: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardBackground)
                .frame(height: cardHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(cardStroke, lineWidth: 1.5)
                )
                .shadow(color: isSelected ? Color.accentColor.opacity(0.3) : .black.opacity(0.1), radius: isSelected ? 8 : 4, y: 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(commit.subject)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .white : .primary)
                
                metadataRow
                decorationRow
            }
            .padding(.horizontal, 16)
            .frame(height: cardHeight)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .scaleEffect(isHovered && !isSelected ? 1.015 : 1.0)
        .shadow(color: isHovered && !isSelected ? Color.accentColor.opacity(0.15) : .clear, radius: 8, y: 2)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
        .onHover { hovering in isHovered = hovering }
        .onTapGesture { onSelect() }
        .contextMenu { contextMenu }
        .padding(.trailing, 16)
    }

    private var cardBackground: Color {
        if isSelected { return Color.accentColor }
        if isSearchMatch { return Color.yellow.opacity(0.15) }
        if isHovered { return Color.white.opacity(0.10) }
        return Color.black.opacity(0.25)
    }

    private var cardStroke: Color {
        if isSelected { return Color.white.opacity(0.6) }
        if isSearchMatch { return Color.yellow.opacity(0.5) }
        if isHovered { return Color.accentColor.opacity(0.35) }
        return Color.white.opacity(0.1)
    }

    private var metadataRow: some View {
        HStack(spacing: 10) {
            Text(commit.shortHash)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(isSelected ? .white.opacity(0.25) : Color.accentColor.opacity(0.15))
                .clipShape(Capsule())
                .foregroundStyle(isSelected ? .white : .accentColor)

            HStack(spacing: 4) {
                Image(systemName: "person.fill").font(.system(size: 9))
                Text(commit.author)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)

            HStack(spacing: 4) {
                Image(systemName: "calendar").font(.system(size: 9))
                Text(Self.dateFormatter.string(from: commit.date))
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(isSelected ? .white.opacity(0.7) : Color.secondary.opacity(0.7))
        }
    }

    private var decorationRow: some View {
        Group {
            if !commit.decorations.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(commit.decorations, id: \.self) { decoration in
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
                    }
                }
            }
        }
    }
}
