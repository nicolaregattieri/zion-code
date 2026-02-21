import Foundation
import SwiftUI

@Observable @MainActor
final class TerminalSession: Identifiable {
    let id = UUID()
    let workingDirectory: URL
    let label: String
    let worktreeID: String?
    var isAlive = true
    var title: String

    // Cache for preserving terminal across SwiftUI view tree changes
    // (split/unsplit restructures the view hierarchy without user intent to close)
    @ObservationIgnored var _cachedView: AnyObject?       // SwiftTerm.TerminalView
    @ObservationIgnored var _processBridge: AnyObject?    // Coordinator (keeps it alive)
    @ObservationIgnored var _shellPid: Int32 = 0
    @ObservationIgnored var _shouldPreserve = true        // false after explicit kill

    init(workingDirectory: URL, label: String, worktreeID: String? = nil) {
        self.workingDirectory = workingDirectory
        self.label = label
        self.worktreeID = worktreeID
        self.title = label
    }

    /// Explicitly kill the terminal process and clear cached state.
    /// Call this only for intentional close (close tab, close pane, switch project).
    func killCachedProcess() {
        DiagnosticLogger.shared.log(.info, "killCachedProcess", context: "\(label)(\(id.uuidString.prefix(4))) pid=\(_shellPid) preserve=\(_shouldPreserve)", source: "TerminalSession")
        _shouldPreserve = false
        if _shellPid > 0 {
            kill(_shellPid, SIGTERM)
        }
        _shellPid = 0
        _cachedView = nil
        _processBridge = nil
    }
}

enum SplitDirection: String {
    case horizontal, vertical
}

@Observable @MainActor
final class TerminalPaneNode: Identifiable {
    let id = UUID()
    var content: PaneContent

    enum PaneContent {
        case terminal(TerminalSession)
        case split(direction: SplitDirection, first: TerminalPaneNode, second: TerminalPaneNode)
    }

    init(session: TerminalSession) {
        self.content = .terminal(session)
    }

    init(direction: SplitDirection, first: TerminalPaneNode, second: TerminalPaneNode) {
        self.content = .split(direction: direction, first: first, second: second)
    }

    /// Collect all terminal sessions in this subtree
    func allSessions() -> [TerminalSession] {
        switch content {
        case .terminal(let session):
            return [session]
        case .split(_, let first, let second):
            return first.allSessions() + second.allSessions()
        }
    }

    /// Find the node containing a specific session ID, returning the parent and which side
    func findNode(containing sessionID: UUID) -> TerminalPaneNode? {
        switch content {
        case .terminal(let session):
            return session.id == sessionID ? self : nil
        case .split(_, let first, let second):
            return first.findNode(containing: sessionID) ?? second.findNode(containing: sessionID)
        }
    }

    /// Flatten consecutive same-direction splits into a single array of children.
    /// Stops at direction boundaries (different-direction splits become leaf nodes).
    func flattenedChildren(forDirection target: SplitDirection) -> [TerminalPaneNode] {
        switch content {
        case .terminal:
            return [self]
        case .split(let direction, let first, let second):
            if direction == target {
                return first.flattenedChildren(forDirection: target)
                     + second.flattenedChildren(forDirection: target)
            } else {
                return [self]
            }
        }
    }

    /// Find parent of a node containing sessionID, returns (parent, isFirst)
    func findParent(of sessionID: UUID) -> (parent: TerminalPaneNode, isFirst: Bool)? {
        guard case .split(_, let first, let second) = content else { return nil }
        if case .terminal(let s) = first.content, s.id == sessionID {
            return (self, true)
        }
        if case .terminal(let s) = second.content, s.id == sessionID {
            return (self, false)
        }
        // Recurse into children
        if let found = first.findParent(of: sessionID) { return found }
        if let found = second.findParent(of: sessionID) { return found }
        return nil
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

// MARK: - Diff Models

struct DiffHunk: Identifiable {
    let id = UUID()
    let header: String
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let lines: [DiffLine]
}

struct DiffLine: Identifiable {
    let id = UUID()
    let type: LineType
    let content: String
    let oldLineNumber: Int?
    let newLineNumber: Int?

    enum LineType {
        case context, addition, deletion
    }
}

struct FileDiff: Identifiable {
    let id = UUID()
    let oldPath: String
    let newPath: String
    let headerLines: [String]
    let hunks: [DiffHunk]
}

// MARK: - Reflog Models

struct ReflogEntry: Identifiable {
    let id = UUID()
    let hash: String
    let shortHash: String
    let refName: String
    let action: String
    let message: String
    let date: Date
    let relativeDate: String
}

// MARK: - Interactive Rebase Models

struct RebaseItem: Identifiable {
    let id = UUID()
    let hash: String
    let shortHash: String
    let subject: String
    var action: RebaseAction = .pick
}

enum RebaseAction: String, CaseIterable, Identifiable {
    case pick, reword, edit, squash, fixup, drop
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pick: return "pick"
        case .reword: return "reword"
        case .edit: return "edit"
        case .squash: return "squash"
        case .fixup: return "fixup"
        case .drop: return "drop"
        }
    }
    var icon: String {
        switch self {
        case .pick: return "checkmark.circle"
        case .reword: return "pencil.circle"
        case .edit: return "pause.circle"
        case .squash: return "arrow.triangle.merge"
        case .fixup: return "arrow.triangle.merge"
        case .drop: return "trash.circle"
        }
    }
    var color: Color {
        switch self {
        case .pick: return .green
        case .reword: return .blue
        case .edit: return .orange
        case .squash: return .purple
        case .fixup: return .purple
        case .drop: return .red
        }
    }
}

// MARK: - Submodule Models

struct SubmoduleInfo: Identifiable {
    let name: String
    let path: String
    let url: String
    let hash: String
    let status: SubmoduleStatus
    var id: String { path }

    enum SubmoduleStatus {
        case upToDate, modified, uninitialized

        var label: String {
            switch self {
            case .upToDate: return L10n("OK")
            case .modified: return L10n("Modificado")
            case .uninitialized: return L10n("Nao inicializado")
            }
        }

        var icon: String {
            switch self {
            case .upToDate: return "checkmark.circle.fill"
            case .modified: return "exclamationmark.circle.fill"
            case .uninitialized: return "circle.dashed"
            }
        }

        var color: Color {
            switch self {
            case .upToDate: return .green
            case .modified: return .orange
            case .uninitialized: return .secondary
            }
        }
    }
}

// MARK: - Repository Statistics

struct RepositoryStats {
    let totalCommits: Int
    let totalBranches: Int
    let totalTags: Int
    let contributors: [ContributorStat]
    let languageBreakdown: [LanguageStat]
    let firstCommitDate: Date?
    let lastCommitDate: Date?
}

struct ContributorStat: Identifiable {
    let name: String
    let email: String
    let commitCount: Int
    var id: String { email }
}

struct LanguageStat: Identifiable {
    let language: String
    let fileCount: Int
    let percentage: Double
    var id: String { language }
}

// MARK: - Conflict Resolution Models

struct ConflictFile: Identifiable, Hashable {
    let path: String
    var isResolved: Bool = false
    var id: String { path }
}

struct ConflictRegion: Identifiable {
    let id = UUID()
    let oursLines: [String]
    let theirsLines: [String]
    let oursLabel: String
    let theirsLabel: String
    var choice: ConflictChoice = .undecided

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: ConflictRegion, rhs: ConflictRegion) -> Bool { lhs.id == rhs.id }
}

enum ConflictChoice: Equatable {
    case undecided, ours, theirs, both, bothReverse, custom(String)
}

/// A block in a conflict file — either context (non-conflicting) or a conflict region
enum ConflictBlock: Identifiable {
    case context([String])
    case conflict(ConflictRegion)

    var id: String {
        switch self {
        case .context(let lines): return "ctx-\(lines.hashValue)"
        case .conflict(let region): return region.id.uuidString
        }
    }
}

// MARK: - AI Review Models

struct ReviewFinding: Identifiable {
    let id = UUID()
    let severity: ReviewSeverity
    let file: String
    let message: String

    enum ReviewSeverity: String {
        case critical, warning, suggestion

        var color: Color {
            switch self {
            case .critical: return .red
            case .warning: return .orange
            case .suggestion: return .blue
            }
        }

        var icon: String {
            switch self {
            case .critical: return "exclamationmark.octagon.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .suggestion: return "lightbulb.fill"
            }
        }

        var label: String {
            switch self {
            case .critical: return L10n("Critico")
            case .warning: return L10n("Aviso")
            case .suggestion: return L10n("Sugestao")
            }
        }
    }
}

struct CommitSuggestion: Identifiable {
    let id = UUID()
    let message: String
    let files: [String]
}

enum EditorTheme: String, CaseIterable, Identifiable {
    case dracula, cityLights, githubLight, catppuccinMocha, oneDarkPro, tokyoNight
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dracula: return "Dracula"
        case .cityLights: return "City Lights"
        case .githubLight: return "GitHub Light"
        case .catppuccinMocha: return "Catppuccin Mocha"
        case .oneDarkPro: return "One Dark Pro"
        case .tokyoNight: return "Tokyo Night"
        }
    }
    var isDark: Bool { true } // GOLDEN RULE — always true for ALL themes

    /// Visual appearance — true light theme (light bg, dark text)
    var isLightAppearance: Bool {
        switch self {
        case .githubLight: return true
        case .dracula, .cityLights, .catppuccinMocha, .oneDarkPro, .tokyoNight: return false
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
        case .catppuccinMocha: return DesignSystem.EditorThemes.catppuccinMocha
        case .oneDarkPro: return DesignSystem.EditorThemes.oneDarkPro
        case .tokyoNight: return DesignSystem.EditorThemes.tokyoNight
        }
    }

    var terminalPalette: TerminalPalette {
        switch self {
        case .dracula: return DesignSystem.TerminalPalettes.dracula
        case .cityLights: return DesignSystem.TerminalPalettes.cityLights
        case .githubLight: return DesignSystem.TerminalPalettes.githubLight
        case .catppuccinMocha: return DesignSystem.TerminalPalettes.catppuccinMocha
        case .oneDarkPro: return DesignSystem.TerminalPalettes.oneDarkPro
        case .tokyoNight: return DesignSystem.TerminalPalettes.tokyoNight
        }
    }
}

enum ConfirmationMode: String, CaseIterable, Identifiable, Sendable {
    case never, destructiveOnly, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .never: return L10n("Nunca confirmar")
        case .destructiveOnly: return L10n("Confirmar criticas")
        case .all: return L10n("Confirmar todas")
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

enum PushDivergenceState {
    case clear
    case behind(Int)
    case diverged(ahead: Int, behind: Int)
}

// MARK: - Zion Map (Help Detail Navigation)

enum FeatureSection: String, CaseIterable, Identifiable {
    case tree, code, terminal, clipboard, operations, worktrees, ai,
         customization, diagnostics, conflicts, settings, diffExplanation,
         codeReview, prInbox, autoUpdates
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .tree: return "point.3.connected.trianglepath.dotted"
        case .code: return "terminal.fill"
        case .terminal: return "rectangle.split.1x2"
        case .clipboard: return "clipboard"
        case .operations: return "gearshape.2.fill"
        case .worktrees: return "arrow.triangle.branch"
        case .ai: return "sparkles"
        case .customization: return "globe"
        case .diagnostics: return "doc.text.magnifyingglass"
        case .conflicts: return "exclamationmark.triangle.fill"
        case .settings: return "gearshape"
        case .diffExplanation: return "sparkles"
        case .codeReview: return "doc.text.magnifyingglass"
        case .prInbox: return "tray.full.fill"
        case .autoUpdates: return "arrow.triangle.2.circlepath"
        }
    }

    var color: Color {
        switch self {
        case .tree: return .purple
        case .code: return .green
        case .terminal: return .blue
        case .clipboard: return .orange
        case .operations: return .indigo
        case .worktrees: return .teal
        case .ai: return .pink
        case .customization: return .cyan
        case .diagnostics: return .gray
        case .conflicts: return .orange
        case .settings: return .gray
        case .diffExplanation: return .purple
        case .codeReview: return .indigo
        case .prInbox: return .mint
        case .autoUpdates: return .green
        }
    }

    var titleKey: String {
        switch self {
        case .tree: return "Zion Tree"
        case .code: return "Zion Code"
        case .terminal: return "Terminal"
        case .clipboard: return "Clipboard Inteligente"
        case .operations: return "Centro de Operacoes"
        case .worktrees: return "Worktrees"
        case .ai: return "Assistente IA"
        case .customization: return "help.customization.title"
        case .diagnostics: return "help.diagnostics.title"
        case .conflicts: return "help.conflicts.title"
        case .settings: return "help.settings.title"
        case .diffExplanation: return "help.diffExplanation.title"
        case .codeReview: return "help.codeReview.title"
        case .prInbox: return "help.prInbox.title"
        case .autoUpdates: return "help.updates.title"
        }
    }

    var subtitleKey: String {
        "map.\(rawValue).subtitle"
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case code, graph, operations
    var id: String { rawValue }
    var title: String {
        switch self {
        case .code: return "Zion Code"
        case .graph: return "Zion Tree"
        case .operations: return "Operacoes"
        }
    }
    var icon: String {
        switch self {
        case .graph: return "point.3.connected.trianglepath.dotted"
        case .code: return "terminal.fill"
        case .operations: return "gearshape"
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
        case .system: return L10n("Sistema")
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
        
        let resName = self.rawValue
        // Try to find the lproj bundle in the module's resource bundle
        if let url = Bundle.module.url(forResource: resName, withExtension: "lproj"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        
        // Fallback: try search in subdirectories if processing messed with structure
        if let path = Bundle.module.path(forResource: resName, ofType: "lproj", inDirectory: nil) ?? 
                      Bundle.module.path(forResource: resName, ofType: "lproj", inDirectory: "Resources"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        
        return .module
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return L10n("Sistema")
        case .light: return L10n("Claro")
        case .dark: return L10n("Escuro")
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

func L10n(_ key: String, _ args: CVarArg...) -> String {
    let languageRaw = UserDefaults.standard.string(forKey: "zion.uiLanguage") ?? "system"
    let language: AppLanguage
    
    if languageRaw == "system" {
        // Find best match for system language
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if preferred.hasPrefix("pt") { language = .ptBR }
        else if preferred.hasPrefix("es") { language = .es }
        else { language = .en }
    } else {
        language = AppLanguage(rawValue: languageRaw) ?? .system
    }
    
    let format = language.bundle.localizedString(forKey: key, value: nil, table: nil)
    
    if args.isEmpty { return format }
    
    return withVaList(args) { vaList in
        return NSString(format: format, locale: language.locale, arguments: vaList) as String
    }
}

enum AIProvider: String, CaseIterable, Identifiable {
    case none, anthropic, openai, gemini
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return L10n("Desativado")
        case .anthropic: return L10n("Anthropic (Claude)")
        case .openai: return L10n("OpenAI (GPT)")
        case .gemini: return L10n("Google (Gemini)")
        }
    }
}

enum CommitMessageStyle: String, CaseIterable, Identifiable {
    case compact, detailed
    var id: String { rawValue }
    var label: String {
        switch self {
        case .compact: return L10n("Compacto")
        case .detailed: return L10n("Detalhado")
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
        case .custom: return L10n("Selecionar do Disco...")
        }
    }
}

// MARK: - Phase 2: Diff Explanation Models

enum DiffExplanationDepth: String, CaseIterable, Identifiable {
    case quick, detailed
    var id: String { rawValue }
    var label: String {
        switch self {
        case .quick: return L10n("settings.diff.depth.quick")
        case .detailed: return L10n("settings.diff.depth.detailed")
        }
    }
}

struct DiffExplanation: Sendable {
    let intent: String
    let risks: String
    let narrative: String
    let severity: DiffExplanationSeverity

    enum DiffExplanationSeverity: String, Sendable {
        case safe, moderate, risky

        var color: Color {
            switch self {
            case .safe: return .green
            case .moderate: return .orange
            case .risky: return .red
            }
        }

        var label: String {
            switch self {
            case .safe: return L10n("diff.severity.safe")
            case .moderate: return L10n("diff.severity.moderate")
            case .risky: return L10n("diff.severity.risky")
            }
        }
    }
}

// MARK: - Phase 3: Code Review Models

struct CodeReviewFile: Identifiable {
    let id = UUID()
    let path: String
    let status: FileChangeStatus
    let additions: Int
    let deletions: Int
    var findings: [ReviewFinding] = []
    var explanation: DiffExplanation?
    var diff: String = ""
    var hunks: [DiffHunk] = []
    var isReviewed: Bool = false
}

enum FileChangeStatus: String, Sendable {
    case added, modified, deleted, renamed

    var icon: String {
        switch self {
        case .added: return "plus.circle.fill"
        case .modified: return "pencil.circle.fill"
        case .deleted: return "minus.circle.fill"
        case .renamed: return "arrow.right.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .added: return .green
        case .modified: return .orange
        case .deleted: return .red
        case .renamed: return .blue
        }
    }

    var label: String {
        switch self {
        case .added: return L10n("file.status.added")
        case .modified: return L10n("file.status.modified")
        case .deleted: return L10n("file.status.deleted")
        case .renamed: return L10n("file.status.renamed")
        }
    }
}

struct CodeReviewStats {
    let totalFiles: Int
    let totalAdditions: Int
    let totalDeletions: Int
    let commitCount: Int
    let criticalCount: Int
    let warningCount: Int
    let suggestionCount: Int

    var overallRisk: DiffExplanation.DiffExplanationSeverity {
        if criticalCount > 0 { return .risky }
        if warningCount > 2 { return .moderate }
        return .safe
    }
}

// MARK: - Phase 4: PR Review Queue Models

enum PRReviewStatus: String, Sendable {
    case pending, reviewing, reviewed, clean

    var label: String {
        switch self {
        case .pending: return L10n("pr.status.pending")
        case .reviewing: return L10n("pr.status.reviewing")
        case .reviewed: return L10n("pr.status.reviewed")
        case .clean: return L10n("pr.status.clean")
        }
    }

    var color: Color {
        switch self {
        case .pending: return .secondary
        case .reviewing: return .blue
        case .reviewed: return .orange
        case .clean: return .green
        }
    }
}

struct PRReviewItem: Identifiable {
    let pr: GitHubPRInfo
    var status: PRReviewStatus = .pending
    var findings: [ReviewFinding] = []
    var reviewedAt: Date?
    var id: Int { pr.id }

    var severitySummary: String {
        let critical = findings.filter { $0.severity == .critical }.count
        let warning = findings.filter { $0.severity == .warning }.count
        if critical > 0 { return "\(critical) critical" }
        if warning > 0 { return "\(warning) warn" }
        if findings.isEmpty && status == .reviewed { return L10n("pr.status.clean") }
        return ""
    }
}
