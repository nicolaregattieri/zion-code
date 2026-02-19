import Foundation
import SwiftUI

@MainActor
final class TerminalSession: ObservableObject, Identifiable {
    let id = UUID()
    let workingDirectory: URL
    let label: String
    let worktreeID: String?
    @Published var isAlive = true
    @Published var title: String

    init(workingDirectory: URL, label: String, worktreeID: String? = nil) {
        self.workingDirectory = workingDirectory
        self.label = label
        self.worktreeID = worktreeID
        self.title = label
    }
}

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
    case dracula, cityLights, githubLight
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dracula: return "Dracula"
        case .cityLights: return "City Lights"
        case .githubLight: return "GitHub Light"
        }
    }
    var isDark: Bool {
        switch self {
        case .dracula, .cityLights, .githubLight: return true
        }
    }

    /// Visual appearance — true light theme (light bg, dark text)
    var isLightAppearance: Bool {
        switch self {
        case .githubLight: return true
        case .dracula, .cityLights: return false
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

    // Concrete sRGB NSColors for AppKit text rendering
    let nsBackground: NSColor
    let nsText: NSColor
    let nsKeyword: NSColor
    let nsType: NSColor
    let nsString: NSColor
    let nsComment: NSColor
    let nsNumber: NSColor

    init(
        background: (r: CGFloat, g: CGFloat, b: CGFloat),
        text: (r: CGFloat, g: CGFloat, b: CGFloat),
        keyword: (r: CGFloat, g: CGFloat, b: CGFloat),
        type: (r: CGFloat, g: CGFloat, b: CGFloat),
        string: (r: CGFloat, g: CGFloat, b: CGFloat),
        comment: (r: CGFloat, g: CGFloat, b: CGFloat),
        number: (r: CGFloat, g: CGFloat, b: CGFloat)
    ) {
        self.background = Color(red: background.r, green: background.g, blue: background.b)
        self.text = Color(red: text.r, green: text.g, blue: text.b)
        self.keyword = Color(red: keyword.r, green: keyword.g, blue: keyword.b)
        self.type = Color(red: type.r, green: type.g, blue: type.b)
        self.string = Color(red: string.r, green: string.g, blue: string.b)
        self.comment = Color(red: comment.r, green: comment.g, blue: comment.b)
        self.number = Color(red: number.r, green: number.g, blue: number.b)

        self.nsBackground = NSColor(srgbRed: background.r, green: background.g, blue: background.b, alpha: 1)
        self.nsText = NSColor(srgbRed: text.r, green: text.g, blue: text.b, alpha: 1)
        self.nsKeyword = NSColor(srgbRed: keyword.r, green: keyword.g, blue: keyword.b, alpha: 1)
        self.nsType = NSColor(srgbRed: type.r, green: type.g, blue: type.b, alpha: 1)
        self.nsString = NSColor(srgbRed: string.r, green: string.g, blue: string.b, alpha: 1)
        self.nsComment = NSColor(srgbRed: comment.r, green: comment.g, blue: comment.b, alpha: 1)
        self.nsNumber = NSColor(srgbRed: number.r, green: number.g, blue: number.b, alpha: 1)
    }
}

extension EditorTheme {
    var colors: ThemeColors {
        switch self {
        case .dracula: return DesignSystem.EditorThemes.dracula
        case .cityLights: return DesignSystem.EditorThemes.cityLights
        case .githubLight: return DesignSystem.EditorThemes.githubLight
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
    case graph, code, operations
    var id: String { rawValue }
    var title: String {
        switch self {
        case .graph: return "Git Graph"
        case .code: return "Vibe Code"
        case .operations: return "Operacoes"
        }
    }
    var icon: String {
        switch self {
        case .graph: return "point.3.connected.trianglepath.dotted"
        case .code: return "terminal.fill"
        case .operations: return "terminal"
        }
    }
    var subtitle: String {
        switch self {
        case .graph: return "Historico visual"
        case .code: return "Editor e Terminal"
        case .operations: return "Acoes e Comandos"
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
