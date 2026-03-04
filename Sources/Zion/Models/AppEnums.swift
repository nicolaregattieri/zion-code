import Foundation
import SwiftUI

// MARK: - Localization

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

// MARK: - Appearance

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

// MARK: - Keep Awake

enum KeepAwakeDuration: String, CaseIterable, Identifiable {
    case off, oneHour, twoHours, fourHours, eightHours, indefinite
    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return L10n("keepAwake.duration.off")
        case .oneHour: return L10n("keepAwake.duration.1h")
        case .twoHours: return L10n("keepAwake.duration.2h")
        case .fourHours: return L10n("keepAwake.duration.4h")
        case .eightHours: return L10n("keepAwake.duration.8h")
        case .indefinite: return L10n("keepAwake.duration.indefinite")
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .off: return 0
        case .oneHour: return 3600
        case .twoHours: return 7200
        case .fourHours: return 14400
        case .eightHours: return 28800
        case .indefinite: return nil
        }
    }
}

// MARK: - Settings Enums

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

// MARK: - AI

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

// MARK: - App Navigation

enum FeatureSection: String, CaseIterable, Identifiable {
    case tree, code, terminal, clipboard, operations, worktrees, ai,
         customization, diagnostics, conflicts, settings, diffExplanation,
         codeReview, prInbox, autoUpdates, zionMode, mobileAccess, bisect,
         clone, repoStats, remotes, submodules, hosting
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
        case .zionMode: return "bolt.fill"
        case .mobileAccess: return "iphone.and.arrow.forward"
        case .bisect: return "arrow.triangle.swap"
        case .clone: return "square.and.arrow.down"
        case .repoStats: return "chart.bar.fill"
        case .remotes: return "network"
        case .submodules: return "shippingbox.fill"
        case .hosting: return "server.rack"
        }
    }

    var color: Color {
        switch self {
        case .tree: return DesignSystem.Colors.brandPrimary
        case .code: return DesignSystem.Colors.success
        case .terminal: return DesignSystem.Colors.info
        case .clipboard: return DesignSystem.Colors.warning
        case .operations: return DesignSystem.Colors.codeReview
        case .worktrees: return DesignSystem.Colors.commitSplit
        case .ai: return DesignSystem.Colors.ai
        case .customization: return DesignSystem.Colors.commitSplit
        case .diagnostics: return .gray
        case .conflicts: return DesignSystem.Colors.warning
        case .settings: return .gray
        case .diffExplanation: return DesignSystem.Colors.ai
        case .codeReview: return DesignSystem.Colors.codeReview
        case .prInbox: return DesignSystem.Colors.commitSplit
        case .autoUpdates: return DesignSystem.Colors.success
        case .zionMode: return .purple
        case .mobileAccess: return DesignSystem.Colors.info
        case .bisect: return DesignSystem.Colors.destructive
        case .clone: return DesignSystem.Colors.success
        case .repoStats: return DesignSystem.Colors.info
        case .remotes: return DesignSystem.Colors.commitSplit
        case .submodules: return DesignSystem.Colors.warning
        case .hosting: return DesignSystem.Colors.brandPrimary
        }
    }

    var titleKey: String {
        switch self {
        case .tree: return "Zion Tree"
        case .code: return "Zion Code"
        case .terminal: return "Terminal"
        case .clipboard: return "Clipboard Inteligente"
        case .operations: return "Zion Ops"
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
        case .zionMode: return "help.zionMode.title"
        case .mobileAccess: return "help.mobileAccess.title"
        case .bisect: return "help.bisect.title"
        case .clone: return "help.clone.title"
        case .repoStats: return "help.repoStats.title"
        case .remotes: return "help.remotes.title"
        case .submodules: return "help.submodules.title"
        case .hosting: return "help.hosting.title"
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
        case .operations: return "Zion Ops"
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
        case .graph: return L10n("sidebar.graph.subtitle")
        case .code: return L10n("sidebar.code.subtitle")
        case .operations: return L10n("sidebar.operations.subtitle")
        }
    }
}
