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
    
    private let rowHeight: CGFloat = 102
    private let cardHeight: CGFloat = 86

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    var body: some View {
        HStack(spacing: 0) {
            LaneGraphView(
                commit: commit,
                laneCount: laneCount,
                isSelected: isSelected,
                isHead: commit.decorations.contains(where: { $0.contains("HEAD") }),
                height: rowHeight
            )
            .onTapGesture { onSelect() }

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.accentColor : (isSearchMatch ? Color.yellow.opacity(0.15) : Color.black.opacity(0.25)))
                    .frame(height: cardHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected ? Color.white.opacity(0.4) : (isSearchMatch ? Color.yellow.opacity(0.5) : Color.white.opacity(0.1)), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(isSelected ? 0.2 : 0.1), radius: 4, y: 2)

                VStack(alignment: .leading, spacing: 6) {
                    Text(commit.subject)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? .white : .primary)
                    
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
                .padding(.horizontal, 16)
                .frame(height: cardHeight)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .onTapGesture { onSelect() }
            .contextMenu { contextMenu }
            .padding(.trailing, 16)
        }
        .frame(height: rowHeight)
        .clipped()
    }
}
