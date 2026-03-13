import AppKit
import Combine
import SwiftUI

enum ShortcutContext: String, CaseIterable, Codable {
    case global
    case editor
    case fileBrowser
    case terminal
    case graph
}

enum ShortcutSection: Int, CaseIterable {
    case navigation
    case editor
    case terminal
    case graph
    case general

    var title: String {
        switch self {
        case .navigation:
            return L10n("Navegacao")
        case .editor:
            return L10n("Editor")
        case .terminal:
            return L10n("Terminal")
        case .graph:
            return L10n("Grafo")
        case .general:
            return L10n("shortcuts.general")
        }
    }

    var icon: String {
        switch self {
        case .navigation:
            return "sidebar.left"
        case .editor:
            return "doc.text"
        case .terminal:
            return "terminal"
        case .graph:
            return "point.3.connected.trianglepath.dotted"
        case .general:
            return "gearshape"
        }
    }
}

enum ShortcutActionID: String, CaseIterable, Codable, Hashable {
    case navigateCode
    case navigateGraph
    case navigateOperations
    case quickOpen
    case toggleSidebar
    case save
    case newFile
    case saveAs
    case find
    case findAlias
    case findReplace
    case findInFiles
    case goToLine
    case findPrevious
    case toggleComment
    case deleteSelection
    case selectNextOccurrence
    case goToDefinition
    case findReferences
    case gitBlame
    case formatDocument
    case toggleDotfiles
    case toggleTerminal
    case maximizeTerminal
    case newTerminalTab
    case splitTerminalVertical
    case splitTerminalHorizontal
    case closeTerminalSplit
    case terminalSearch
    case toggleSpeechInput
    case terminalZoomIn
    case terminalZoomOut
    case graphFind
    case bisectGood
    case bisectBad
    case bisectSkip
    case refreshRepository
    case codeReview
    case openSettings
    case zenMode
    case zionMode
    case showKeyboardShortcuts
}

enum ShortcutKey: Codable, Hashable {
    case character(String)
    case delete
    case escape
    case `return`
    case function(Int)

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    private enum Kind: String, Codable {
        case character
        case delete
        case escape
        case `return`
        case function
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .character:
            self = .character(try container.decode(String.self, forKey: .value))
        case .delete:
            self = .delete
        case .escape:
            self = .escape
        case .return:
            self = .return
        case .function:
            self = .function(try container.decode(Int.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .character(let value):
            try container.encode(Kind.character, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .delete:
            try container.encode(Kind.delete, forKey: .kind)
        case .escape:
            try container.encode(Kind.escape, forKey: .kind)
        case .return:
            try container.encode(Kind.return, forKey: .kind)
        case .function(let value):
            try container.encode(Kind.function, forKey: .kind)
            try container.encode(value, forKey: .value)
        }
    }

    var displayString: String {
        switch self {
        case .character(let value):
            return value.uppercased()
        case .delete:
            return "Delete"
        case .escape:
            return "Esc"
        case .return:
            return "Enter"
        case .function(let number):
            return "F\(number)"
        }
    }

    var menuKeyEquivalent: KeyEquivalent? {
        switch self {
        case .character(let value):
            guard let character = value.first else { return nil }
            return KeyEquivalent(character)
        case .delete:
            return .delete
        case .escape:
            return .escape
        case .return:
            return .return
        case .function:
            return nil
        }
    }
}

struct ShortcutModifiers: OptionSet, Hashable, Codable {
    let rawValue: Int

    static let command = ShortcutModifiers(rawValue: 1 << 0)
    static let shift = ShortcutModifiers(rawValue: 1 << 1)
    static let option = ShortcutModifiers(rawValue: 1 << 2)
    static let control = ShortcutModifiers(rawValue: 1 << 3)

    var eventModifiers: EventModifiers {
        var modifiers: EventModifiers = []
        if contains(.command) { modifiers.insert(.command) }
        if contains(.shift) { modifiers.insert(.shift) }
        if contains(.option) { modifiers.insert(.option) }
        if contains(.control) { modifiers.insert(.control) }
        return modifiers
    }

    var displayString: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }
}

struct ShortcutBinding: Codable, Hashable {
    let key: ShortcutKey
    let modifiers: ShortcutModifiers

    var displayString: String {
        modifiers.displayString + key.displayString
    }
}

struct ShortcutDefinition: Identifiable, Hashable {
    let id: ShortcutActionID
    let context: ShortcutContext
    let section: ShortcutSection
    let titleKey: String
    let defaultBinding: ShortcutBinding?

    var title: String {
        L10n(titleKey)
    }
}

@objc protocol ZionShortcutActionTarget {
    @objc optional func zionToggleComment(_ sender: Any?)
    @objc optional func zionDeleteSelectedFiles(_ sender: Any?)
}

@MainActor
final class ShortcutRegistry: ObservableObject {
    static let storageKey = "shortcuts.bindings"
    static let shared = ShortcutRegistry()

    @Published private(set) var overrides: [ShortcutActionID: ShortcutBinding] = [:]

    let definitions: [ShortcutDefinition]

    private let userDefaults: UserDefaults
    private var defaultsObserver: AnyCancellable?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.definitions = Self.makeDefinitions()
        loadOverrides()

        defaultsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.loadOverrides()
                }
            }
    }

    func binding(for action: ShortcutActionID) -> ShortcutBinding? {
        overrides[action] ?? definition(for: action)?.defaultBinding
    }

    func definition(for action: ShortcutActionID) -> ShortcutDefinition? {
        definitions.first { $0.id == action }
    }

    func definitions(in section: ShortcutSection) -> [ShortcutDefinition] {
        definitions.filter { $0.section == section }
    }

    func setOverride(_ binding: ShortcutBinding?, for action: ShortcutActionID) {
        if let binding {
            overrides[action] = binding
        } else {
            overrides.removeValue(forKey: action)
        }
        persistOverrides()
    }

    func displayString(for action: ShortcutActionID) -> String? {
        binding(for: action)?.displayString
    }

    func actions(for binding: ShortcutBinding, in context: ShortcutContext) -> [ShortcutActionID] {
        definitions
            .filter { $0.context == context && self.binding(for: $0.id) == binding }
            .map(\.id)
    }

    func conflicts(for action: ShortcutActionID, binding: ShortcutBinding) -> [ShortcutActionID] {
        guard let context = definition(for: action)?.context else { return [] }
        return actions(for: binding, in: context).filter { $0 != action }
    }

    private func loadOverrides() {
        guard let data = userDefaults.data(forKey: Self.storageKey) else {
            if !overrides.isEmpty {
                overrides = [:]
            }
            return
        }

        guard let decoded = try? JSONDecoder().decode([String: ShortcutBinding].self, from: data) else {
            return
        }

        let mapped = decoded.reduce(into: [ShortcutActionID: ShortcutBinding]()) { result, entry in
            guard let action = ShortcutActionID(rawValue: entry.key) else { return }
            result[action] = entry.value
        }

        if mapped != overrides {
            overrides = mapped
        }
    }

    private func persistOverrides() {
        let encoded = overrides.reduce(into: [String: ShortcutBinding]()) { result, entry in
            result[entry.key.rawValue] = entry.value
        }
        guard let data = try? JSONEncoder().encode(encoded) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
    }

    private static func makeDefinitions() -> [ShortcutDefinition] {
        [
            .init(id: .navigateCode, context: .global, section: .navigation, titleKey: "Codigo", defaultBinding: .init(key: .character("1"), modifiers: [.command])),
            .init(id: .navigateGraph, context: .global, section: .navigation, titleKey: "Grafo", defaultBinding: .init(key: .character("2"), modifiers: [.command])),
            .init(id: .navigateOperations, context: .global, section: .navigation, titleKey: "Zion Ops", defaultBinding: .init(key: .character("3"), modifiers: [.command])),

            .init(id: .quickOpen, context: .editor, section: .editor, titleKey: "Quick Open", defaultBinding: .init(key: .character("p"), modifiers: [.command])),
            .init(id: .toggleSidebar, context: .editor, section: .editor, titleKey: "Barra lateral", defaultBinding: .init(key: .character("b"), modifiers: [.command])),
            .init(id: .save, context: .editor, section: .editor, titleKey: "Salvar", defaultBinding: .init(key: .character("s"), modifiers: [.command])),
            .init(id: .newFile, context: .editor, section: .editor, titleKey: "Novo Arquivo", defaultBinding: .init(key: .character("n"), modifiers: [.command])),
            .init(id: .saveAs, context: .editor, section: .editor, titleKey: "Salvar Como...", defaultBinding: .init(key: .character("s"), modifiers: [.command, .shift])),
            .init(id: .find, context: .editor, section: .editor, titleKey: "shortcuts.find", defaultBinding: .init(key: .character("f"), modifiers: [.command])),
            .init(id: .findAlias, context: .editor, section: .editor, titleKey: "shortcuts.findAlias", defaultBinding: .init(key: .character("f"), modifiers: [.control])),
            .init(id: .findReplace, context: .editor, section: .editor, titleKey: "shortcuts.findReplace", defaultBinding: .init(key: .character("h"), modifiers: [.command])),
            .init(id: .findInFiles, context: .editor, section: .editor, titleKey: "shortcuts.findInFiles", defaultBinding: .init(key: .character("f"), modifiers: [.command, .shift])),
            .init(id: .goToLine, context: .editor, section: .editor, titleKey: "shortcuts.goToLine", defaultBinding: .init(key: .character("g"), modifiers: [.command])),
            .init(id: .findPrevious, context: .editor, section: .editor, titleKey: "shortcuts.findPrevious", defaultBinding: .init(key: .character("g"), modifiers: [.command, .shift])),
            .init(id: .toggleComment, context: .editor, section: .editor, titleKey: "shortcuts.toggleComment", defaultBinding: .init(key: .character("/"), modifiers: [.command])),
            .init(id: .deleteSelection, context: .fileBrowser, section: .editor, titleKey: "Excluir", defaultBinding: .init(key: .delete, modifiers: [.command])),
            .init(id: .selectNextOccurrence, context: .editor, section: .editor, titleKey: "shortcuts.selectNextOccurrence", defaultBinding: .init(key: .character("d"), modifiers: [.command])),
            .init(id: .goToDefinition, context: .editor, section: .editor, titleKey: "shortcuts.goToDefinition", defaultBinding: .init(key: .function(12), modifiers: [])),
            .init(id: .findReferences, context: .editor, section: .editor, titleKey: "shortcuts.findReferences", defaultBinding: .init(key: .function(12), modifiers: [.shift])),
            .init(id: .gitBlame, context: .editor, section: .editor, titleKey: "Git Blame", defaultBinding: .init(key: .character("b"), modifiers: [.command, .shift])),
            .init(id: .formatDocument, context: .editor, section: .editor, titleKey: "shortcuts.formatDocument", defaultBinding: .init(key: .character("f"), modifiers: [.shift, .option])),
            .init(id: .toggleDotfiles, context: .fileBrowser, section: .editor, titleKey: "shortcuts.toggleDotfiles", defaultBinding: .init(key: .character("h"), modifiers: [.command, .shift])),

            .init(id: .toggleTerminal, context: .terminal, section: .terminal, titleKey: "Terminal", defaultBinding: .init(key: .character("j"), modifiers: [.command])),
            .init(id: .maximizeTerminal, context: .terminal, section: .terminal, titleKey: "Maximizar terminal", defaultBinding: .init(key: .character("j"), modifiers: [.command, .control])),
            .init(id: .newTerminalTab, context: .terminal, section: .terminal, titleKey: "Nova aba", defaultBinding: .init(key: .character("t"), modifiers: [.command])),
            .init(id: .splitTerminalVertical, context: .terminal, section: .terminal, titleKey: "Dividir verticalmente", defaultBinding: .init(key: .character("d"), modifiers: [.command, .shift])),
            .init(id: .splitTerminalHorizontal, context: .terminal, section: .terminal, titleKey: "Dividir horizontalmente", defaultBinding: .init(key: .character("e"), modifiers: [.command, .shift])),
            .init(id: .closeTerminalSplit, context: .terminal, section: .terminal, titleKey: "Fechar painel dividido", defaultBinding: .init(key: .character("w"), modifiers: [.command, .shift])),
            .init(id: .terminalSearch, context: .terminal, section: .terminal, titleKey: "shortcuts.terminalSearch", defaultBinding: .init(key: .character("f"), modifiers: [.command])),
            .init(id: .toggleSpeechInput, context: .terminal, section: .terminal, titleKey: "speech.button.tooltip", defaultBinding: .init(key: .character("x"), modifiers: [.command, .option])),
            .init(id: .terminalZoomIn, context: .terminal, section: .terminal, titleKey: "Zoom in", defaultBinding: .init(key: .character("="), modifiers: [.control])),
            .init(id: .terminalZoomOut, context: .terminal, section: .terminal, titleKey: "Zoom out", defaultBinding: .init(key: .character("-"), modifiers: [.control])),

            .init(id: .graphFind, context: .graph, section: .graph, titleKey: "Buscar no grafo", defaultBinding: .init(key: .character("f"), modifiers: [.command])),
            .init(id: .bisectGood, context: .graph, section: .graph, titleKey: "bisect.good", defaultBinding: .init(key: .character("g"), modifiers: [.command, .shift])),
            .init(id: .bisectBad, context: .graph, section: .graph, titleKey: "bisect.bad", defaultBinding: .init(key: .character("b"), modifiers: [.command, .shift])),
            .init(id: .bisectSkip, context: .graph, section: .graph, titleKey: "bisect.skip", defaultBinding: .init(key: .character("s"), modifiers: [.command, .shift])),

            .init(id: .refreshRepository, context: .global, section: .general, titleKey: "shortcuts.refreshRepository", defaultBinding: .init(key: .character("r"), modifiers: [.command])),
            .init(id: .codeReview, context: .global, section: .general, titleKey: "shortcuts.codeReview", defaultBinding: .init(key: .character("r"), modifiers: [.command, .shift])),
            .init(id: .openSettings, context: .global, section: .general, titleKey: "help.settings.title", defaultBinding: .init(key: .character(","), modifiers: [.command])),
            .init(id: .zenMode, context: .global, section: .general, titleKey: "zen.mode", defaultBinding: .init(key: .character("j"), modifiers: [.command, .shift])),
            .init(id: .zionMode, context: .global, section: .general, titleKey: "shortcuts.zionMode", defaultBinding: .init(key: .character("z"), modifiers: [.command, .control])),
            .init(id: .showKeyboardShortcuts, context: .global, section: .general, titleKey: "Atalhos de Teclado", defaultBinding: .init(key: .character("k"), modifiers: [.command, .option])),
        ]
    }
}
