import SwiftUI

struct DecorationPill: View {
    let decoration: String
    let currentBranch: String
    let highlightSearchQuery: String
    let onCheckout: (String) -> Void
    let branchContextMenu: (String) -> AnyView
    let tagContextMenu: (String) -> AnyView
    let remotes: [String]
    let worktreeBranches: Set<String>
    let rootWorktreeBranches: Set<String>

    var body: some View {
        let (name, type) = parseDecoration(decoration, remotes: remotes)
        let isCurrent = checkIsCurrent(name: name, type: type, current: currentBranch)
        let isMain = ["main", "master", "develop", "dev"].contains(name.lowercased())
        let isBranchDecoration = type == .localBranch || type == .head
        let isWorktreeBranch = isBranchDecoration && worktreeBranches.contains(name)
        let isRootWorktreeBranch = isBranchDecoration && rootWorktreeBranches.contains(name)
        let isSearchMatch = !highlightSearchQuery.isEmpty && name.lowercased().contains(highlightSearchQuery.lowercased())
        let pillColor = color(for: type)
        let isHighlighted = isCurrent || isSearchMatch
        let backgroundColor = pillBackgroundColor(isCurrent: isCurrent, isSearchMatch: isSearchMatch, pillColor: pillColor)
        let foregroundColor = pillForegroundColor(isCurrent: isCurrent, isSearchMatch: isSearchMatch, pillColor: pillColor)
        let borderColor = pillBorderColor(isCurrent: isCurrent, isSearchMatch: isSearchMatch, pillColor: pillColor)

        HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
            if isMain {
                Image(systemName: "shield.fill").font(.system(size: 8))
            } else if type == .tag {
                Image(systemName: "tag.fill").font(.system(size: 7))
            } else if type == .remoteBranch {
                Image(systemName: "icloud.fill").font(.system(size: 8))
            }
            if isCurrent {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 8))
            }

            Text(name)
                .font(.system(size: 10, weight: isHighlighted ? .heavy : .bold, design: .monospaced))
                .lineLimit(1)
                .frame(maxWidth: 200)

            if isRootWorktreeBranch || isWorktreeBranch {
                Text(isRootWorktreeBranch ? L10n("worktree.main.badge") : L10n("worktree.badge.short"))
                    .font(DesignSystem.Typography.monoMetaBold)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(DesignSystem.Colors.commitSplit.opacity(0.2))
                    .clipShape(Capsule())
                    .foregroundStyle(DesignSystem.Colors.commitSplit)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background {
            Capsule()
                .fill(backgroundColor)
        }
        .overlay {
            if isCurrent && !isSearchMatch {
                Capsule()
                    .inset(by: 2)
                    .fill(currentTintColor(for: type))
            }
        }
        .overlay {
            if isCurrent && !isSearchMatch {
                Capsule()
                    .inset(by: 2)
                    .strokeBorder(pillColor.opacity(DesignSystem.Opacity.muted), lineWidth: 1)
            }
        }
        .foregroundStyle(foregroundColor)
        .overlay(
            Capsule()
                .strokeBorder(
                    borderColor,
                    lineWidth: isHighlighted ? 1.5 : 1
                )
        )
        .shadow(color: isCurrent ? DesignSystem.Colors.selectionBackground : .clear, radius: 4, y: 1)
        .onTapGesture(count: 2) {
            if type != .tag { onCheckout(name) }
        }
        .contextMenu {
            if type == .tag {
                tagContextMenu(name)
            } else if type != .other {
                branchContextMenu(name)
            }
        }
        .help(pillHelp(name: name, type: type, isCurrent: isCurrent, isWorktreeBranch: isWorktreeBranch))
        .accessibilityLabel(pillHelp(name: name, type: type, isCurrent: isCurrent, isWorktreeBranch: isWorktreeBranch))
    }

    enum DecorationType {
        case head, localBranch, remoteBranch, tag, other
    }

    private func pillHelp(name: String, type: DecorationType, isCurrent: Bool, isWorktreeBranch: Bool) -> String {
        let worktreeSuffix = isWorktreeBranch ? " " + L10n("worktree.badge.hint") : ""
        if type == .tag {
            return L10n("Tag: %@", name) + worktreeSuffix
        }
        let suffix = isCurrent ? L10n("(Atual)") : L10n("(Double-click para checkout)")
        return L10n("Branch: %@", name) + " " + suffix + worktreeSuffix
    }

    private func checkIsCurrent(name: String, type: DecorationType, current: String) -> Bool {
        if type == .head { return name == current }
        if name == current { return true }
        if current.hasPrefix("detached (tag: ") && type == .tag && current.contains(name) { return true }
        if current.hasPrefix("detached (") && current.contains(name) { return true } // matches hash
        return false
    }

    private func parseDecoration(_ decoration: String, remotes: [String]) -> (String, DecorationType) {
        let trimmed = decoration.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("HEAD -> ") {
            return (String(trimmed.dropFirst(8)), .head)
        } else if trimmed.hasPrefix("tag: ") {
            return (String(trimmed.dropFirst(5)), .tag)
        } else {
            // Check if it's a remote branch: starts with a known remote name followed by '/'
            for remote in remotes {
                if trimmed.hasPrefix("\(remote)/") {
                    return (trimmed, .remoteBranch)
                }
            }
            
            // Fallback for detached HEAD or other refs
            if trimmed == "HEAD" {
                return (trimmed, .other)
            }
            
            // Otherwise it's a local branch (even if it has a slash like feature/...)
            return (trimmed, .localBranch)
        }
    }

    private func color(for type: DecorationType) -> Color {
        switch type {
        case .head: return DesignSystem.Colors.ai
        case .localBranch: return DesignSystem.Colors.success
        case .remoteBranch: return DesignSystem.Colors.warning
        case .tag: return DesignSystem.Colors.searchHighlight
        case .other: return .gray
        }
    }

    private func pillBackgroundColor(isCurrent: Bool, isSearchMatch: Bool, pillColor: Color) -> Color {
        if isSearchMatch { return DesignSystem.Colors.statusYellowBg }
        if isCurrent { return DesignSystem.Colors.glassElevated }
        return pillColor.opacity(DesignSystem.Opacity.selectedSubtle)
    }

    private func pillForegroundColor(isCurrent: Bool, isSearchMatch: Bool, pillColor: Color) -> Color {
        if isSearchMatch || isCurrent { return .primary }
        return pillColor
    }

    private func pillBorderColor(isCurrent: Bool, isSearchMatch: Bool, pillColor: Color) -> Color {
        if isSearchMatch { return DesignSystem.Colors.searchHighlight }
        if isCurrent { return DesignSystem.Colors.selectionBorder }
        return pillColor.opacity(0.2)
    }

    private func currentTintColor(for type: DecorationType) -> Color {
        switch type {
        case .head:
            return DesignSystem.Colors.ai.opacity(DesignSystem.Opacity.faint)
        case .localBranch:
            return DesignSystem.Colors.statusGreenBg
        case .remoteBranch:
            return DesignSystem.Colors.statusOrangeBg
        case .tag:
            return DesignSystem.Colors.statusYellowBg
        case .other:
            return DesignSystem.Colors.glassSubtle
        }
    }
}
