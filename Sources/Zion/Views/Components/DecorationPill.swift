import SwiftUI

struct DecorationPill: View {
    let decoration: String
    let currentBranch: String
    let highlightSearchQuery: String
    let onCheckout: (String) -> Void
    let branchContextMenu: (String) -> AnyView
    let tagContextMenu: (String) -> AnyView
    let remotes: [String]

    var body: some View {
        let (name, type) = parseDecoration(decoration, remotes: remotes)
        let isCurrent = checkIsCurrent(name: name, type: type, current: currentBranch)
        let isMain = ["main", "master", "develop", "dev"].contains(name.lowercased())
        let isSearchMatch = !highlightSearchQuery.isEmpty && name.lowercased().contains(highlightSearchQuery.lowercased())
        let pillColor = color(for: type)
        
        HStack(spacing: 4) {
            if isMain {
                Image(systemName: "shield.fill").font(.system(size: 8))
            } else if type == .tag {
                Image(systemName: "tag.fill").font(.system(size: 7))
            } else if type == .remoteBranch {
                Image(systemName: "icloud.fill").font(.system(size: 8))
            }

            Text(name)
                .font(.system(size: 10, weight: (isCurrent || isSearchMatch) ? .black : .bold, design: .monospaced))
                .lineLimit(1)
                .frame(maxWidth: 200)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(isSearchMatch ? Color.yellow.opacity(0.3) : pillColor.opacity(isCurrent ? 0.25 : 0.12))
        )
        .foregroundStyle(isSearchMatch ? .primary : pillColor)
        .overlay(
            Capsule()
                .strokeBorder(isSearchMatch ? Color.yellow : pillColor.opacity(isCurrent ? 0.6 : 0.2), lineWidth: isSearchMatch ? 2 : 1)
        )
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
        .help(pillHelp(name: name, type: type, isCurrent: isCurrent))
    }

    enum DecorationType {
        case head, localBranch, remoteBranch, tag, other
    }

    private func pillHelp(name: String, type: DecorationType, isCurrent: Bool) -> String {
        if type == .tag {
            return L10n("Tag: %@", name)
        }
        let suffix = isCurrent ? L10n("(Atual)") : L10n("(Double-click para checkout)")
        return L10n("Branch: %@", name) + " " + suffix
    }

    private func checkIsCurrent(name: String, type: DecorationType, current: String) -> Bool {
        if type == .head { return true }
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
        case .head: return .cyan
        case .localBranch: return .green
        case .remoteBranch: return .orange
        case .tag: return .yellow
        case .other: return .gray
        }
    }
}
