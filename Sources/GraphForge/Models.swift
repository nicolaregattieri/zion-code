import Foundation
import SwiftUI

struct LaneEdge: Hashable, Sendable {
    let from: Int
    let to: Int
    let colorKey: Int
}

struct LaneColor: Hashable, Sendable {
    let lane: Int
    let colorKey: Int
}

struct ParsedCommit: Hashable, Sendable {
    let hash: String
    let parents: [String]
    let author: String
    let date: Date
    let subject: String
    let decorations: [String]
}

struct Commit: Identifiable, Hashable, Sendable {
    let id: String
    let shortHash: String
    let parents: [String]
    let author: String
    let date: Date
    let subject: String
    let decorations: [String]
    let lane: Int
    let nodeColorKey: Int
    let incomingLanes: [Int]
    let outgoingLanes: [Int]
    let laneColors: [LaneColor]
    let outgoingEdges: [LaneEdge]
}

struct WorktreeItem: Identifiable, Hashable, Sendable {
    let path: String
    let head: String
    let branch: String
    let isDetached: Bool
    let isLocked: Bool
    let lockReason: String
    let isPrunable: Bool
    let pruneReason: String
    let isCurrent: Bool
    var id: String { path }
}

struct BranchInfo: Identifiable, Hashable, Sendable {
    let name: String
    let fullRef: String
    let head: String
    let upstream: String
    let committerDate: Date
    let isRemote: Bool
    var id: String { name }
    var shortHead: String { String(head.prefix(8)) }
}

struct BranchTreeNode: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let branchName: String?
    let children: [BranchTreeNode]
    var isGroup: Bool { branchName == nil }
    var outlineChildren: [BranchTreeNode]? { children.isEmpty ? nil : children }
}

struct RemoteInfo: Identifiable, Hashable, Sendable {
    let name: String
    let url: String
    var id: String { name }
}

struct FileItem: Identifiable, Hashable, Sendable {
    let url: URL
    let isDirectory: Bool
    let children: [FileItem]?
    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

enum EditorTheme: String, CaseIterable, Identifiable {
    case dracula, cityLights, everforestLight
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dracula: return "Dracula"
        case .cityLights: return "City Lights"
        case .everforestLight: return "Everforest Light"
        }
    }
    var isDark: Bool {
        switch self {
        case .dracula, .cityLights: return true
        case .everforestLight: return false
        }
    }
}

// THEME DEFINITIONS
struct ThemeColors {
    let background: Color
    let text: Color
    let keyword: Color
    let type: Color
    let string: Color
    let comment: Color
    let number: Color
    
    // AppKit versions for the editor
    var nsBackground: NSColor { NSColor(background) }
    var nsText: NSColor { NSColor(text) }
    var nsKeyword: NSColor { NSColor(keyword) }
    var nsType: NSColor { NSColor(type) }
    var nsString: NSColor { NSColor(string) }
    var nsComment: NSColor { NSColor(comment) }
    var nsNumber: NSColor { NSColor(number) }
}

extension EditorTheme {
    var colors: ThemeColors {
        switch self {
        case .dracula:
            return ThemeColors(
                background: Color(red: 0.16, green: 0.16, blue: 0.21),
                text: Color(red: 0.97, green: 0.97, blue: 0.95),
                keyword: Color(red: 1.0, green: 0.48, blue: 0.77),
                type: Color(red: 0.54, green: 0.91, blue: 0.99),
                string: Color(red: 0.95, green: 0.99, blue: 0.47),
                comment: Color(red: 0.38, green: 0.41, blue: 0.53),
                number: Color(red: 0.74, green: 0.57, blue: 0.97)
            )
        case .cityLights:
            return ThemeColors(
                background: Color(red: 0.11, green: 0.15, blue: 0.17),
                text: Color(red: 0.44, green: 0.55, blue: 0.63),
                keyword: Color(red: 0.33, green: 0.60, blue: 0.99),
                type: Color(red: 0.0, green: 0.73, blue: 0.82),
                string: Color(red: 0.55, green: 0.83, blue: 0.61),
                comment: Color(red: 0.25, green: 0.31, blue: 0.37),
                number: Color(red: 0.89, green: 0.49, blue: 0.55)
            )
        case .everforestLight:
            return ThemeColors(
                background: Color(red: 0.99, green: 0.98, blue: 0.93),
                text: Color(red: 0.36, green: 0.42, blue: 0.37),
                keyword: Color(red: 0.55, green: 0.26, blue: 0.32),
                type: Color(red: 0.21, green: 0.45, blue: 0.69),
                string: Color(red: 0.55, green: 0.63, blue: 0.0),
                comment: Color(red: 0.58, green: 0.62, blue: 0.57),
                number: Color(red: 0.87, green: 0.63, blue: 0.0)
            )
        }
    }
}

enum ConfirmationMode: String, CaseIterable, Identifiable, Sendable {
    case never, destructiveOnly, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .never: return "Nunca confirmar"
        case .destructiveOnly: return "Confirmar criticas"
        case .all: return "Confirmar todas"
        }
    }
}

enum PushMode: String, CaseIterable, Identifiable, Sendable {
    case normal, forceWithLease, force
    var id: String { rawValue }
    var label: String {
        switch self {
        case .normal: return "Normal"
        case .forceWithLease: return "Force With Lease"
        case .force: return "Force"
        }
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case graph, changes, code, operations, worktrees
    var id: String { rawValue }
    var title: String {
        switch self {
        case .graph: return "Git Graph"
        case .changes: return "Changes"
        case .code: return "Vibe Code"
        case .operations: return "Operacoes"
        case .worktrees: return "Worktrees"
        }
    }
    var icon: String {
        switch self {
        case .graph: return "point.3.connected.trianglepath.dotted"
        case .changes: return "doc.on.doc"
        case .code: return "terminal.fill"
        case .operations: return "terminal"
        case .worktrees: return "square.split.2x2"
        }
    }
    var subtitle: String {
        switch self {
        case .graph: return "Historico visual"
        case .changes: return "Arquivos modificados"
        case .code: return "Editor e Terminal"
        case .operations: return "Acoes e Comandos"
        case .worktrees: return "Contextos paralelos"
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, ptBR = "pt-BR", en, es
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "Sistema"
        case .ptBR: return "Português (BR)"
        case .en: return "English"
        case .es: return "Español"
        }
    }
    var locale: Locale {
        switch self {
        case .system: return .autoupdatingCurrent
        case .ptBR: return Locale(identifier: "pt-BR")
        case .en: return Locale(identifier: "en")
        case .es: return Locale(identifier: "es")
        }
    }
    
    var bundle: Bundle {
        if self == .system { return .module }
        // Try exact match then lowercase match
        let resName = self.rawValue
        if let path = Bundle.module.path(forResource: resName, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        if let path = Bundle.module.path(forResource: resName.lowercased(), ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .module
    }
}

func L10n(_ key: String, _ args: CVarArg...) -> String {
    let languageRaw = UserDefaults.standard.string(forKey: "graphforge.uiLanguage") ?? "system"
    let language = AppLanguage(rawValue: languageRaw) ?? .system
    let format = language.bundle.localizedString(forKey: key, value: nil, table: nil)
    
    if args.isEmpty { return format }
    
    return withVaList(args) { vaList in
        return NSString(format: format, locale: language.locale, arguments: vaList) as String
    }
}

enum ExternalEditor: String, CaseIterable, Identifiable {
    case vscode = "com.microsoft.VSCode"
    case cursor = "com.todesktop.230313mzl4w4u92"
    case antigravity = "com.antigravity.Antigravity"
    case xcode = "com.apple.dt.Xcode"
    case intellij = "com.jetbrains.intellij"
    case sublime = "com.sublimetext.4"
    case custom = "custom"
    
    var id: String { rawValue }
    var label: String {
        switch self {
        case .vscode: return "VS Code"
        case .cursor: return "Cursor"
        case .antigravity: return "Antigravity"
        case .xcode: return "Xcode"
        case .intellij: return "IntelliJ"
        case .sublime: return "Sublime Text"
        case .custom: return "Selecionar do Disco..."
        }
    }
}

enum ExternalTerminal: String, CaseIterable, Identifiable {
    case terminal = "com.apple.Terminal"
    case iterm = "com.googlecode.iterm2"
    case warp = "dev.warp.Warp-Stable"
    case custom = "custom"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .terminal: return "Terminal.app"
        case .iterm: return "iTerm2"
        case .warp: return "Warp"
        case .custom: return "Selecionar do Disco..."
        }
    }
}
