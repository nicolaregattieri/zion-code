import SwiftUI
import Sparkle
import UniformTypeIdentifiers

extension Notification.Name {
    static let showKeyboardShortcuts = Notification.Name("showKeyboardShortcuts")
    static let showHelp = Notification.Name("showHelp")
    static let showOnboarding = Notification.Name("showOnboarding")
    static let toggleZenMode = Notification.Name("toggleZenMode")
    static let toggleZionMode = Notification.Name("toggleZionMode")
    static let openFilesFromFinder = Notification.Name("openFilesFromFinder")
    static let formatDocument = Notification.Name("formatDocument")
    static let formatCodeFile = Notification.Name("formatCodeFile")
    static let openMobileAccessSettings = Notification.Name("openMobileAccessSettings")
    static let openAISettings = Notification.Name("openAISettings")
    static let refreshRepoMemory = Notification.Name("refreshRepoMemory")
    static let clearRepoMemory = Notification.Name("clearRepoMemory")
}

@main
struct ZionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var updater = SparkleUpdater()
    @StateObject private var shortcutRegistry = ShortcutRegistry.shared
    @AppStorage("zion.uiLanguage") private var uiLanguageRaw: String = AppLanguage.system.rawValue

    private var uiLanguage: AppLanguage { AppLanguage(rawValue: uiLanguageRaw) ?? .system }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .id(uiLanguageRaw)
                .environment(\.locale, uiLanguage.locale)
                .environmentObject(shortcutRegistry)
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1360, height: 840)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L10n("Sobre o Zion")) {
                    showAboutPanel()
                }
            }

            CommandMenu(L10n("format.menu")) {
                shortcutCommandButton(L10n("format.document"), action: .formatDocument) {
                    NotificationCenter.default.post(name: .formatDocument, object: nil)
                }

                shortcutCommandButton(L10n("shortcuts.toggleComment"), action: .toggleComment) {
                    NSApp.sendAction(#selector(ZionShortcutActionTarget.zionToggleComment(_:)), to: nil, from: nil)
                }
            }

            CommandMenu(L10n("focus.menu")) {
                Button(L10n("zen.mode")) {
                    NotificationCenter.default.post(name: .toggleZenMode, object: nil)
                }
                .keyboardShortcut("J", modifiers: [.command, .shift])

                Button("Zion Mode") {
                    NotificationCenter.default.post(name: .toggleZionMode, object: nil)
                }
                .keyboardShortcut("z", modifiers: [.command, .control])
            }

            CommandGroup(replacing: .help) {
                Button(L10n("Conheca o Zion")) {
                    NotificationCenter.default.post(name: .showHelp, object: nil)
                }

                Divider()

                Button(L10n("Atalhos de Teclado")) {
                    NotificationCenter.default.post(name: .showKeyboardShortcuts, object: nil)
                }
                .applyShortcutBinding(shortcutRegistry.binding(for: .showKeyboardShortcuts))

                Divider()

                Button(L10n("Buscar Atualizacoes...")) {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)

                Divider()

                Button(L10n("Exportar Diagnostico...")) {
                    exportDiagnosticLog()
                }

                Button(L10n("Copiar Diagnostico")) {
                    copyDiagnosticLog()
                }
            }

            CommandGroup(after: .pasteboard) {
                shortcutCommandButton(L10n("Excluir"), action: .deleteSelection) {
                    NSApp.sendAction(#selector(ZionShortcutActionTarget.zionDeleteSelectedFiles(_:)), to: nil, from: nil)
                }
            }
        }

        Settings {
            SettingsView()
                .id(uiLanguageRaw)
                .environment(\.locale, uiLanguage.locale)
                .environmentObject(shortcutRegistry)
        }
    }

    @ViewBuilder
    private func shortcutCommandButton(_ title: String, action: ShortcutActionID, perform: @escaping () -> Void) -> some View {
        Button(title, action: perform)
            .applyShortcutBinding(shortcutRegistry.binding(for: action))
    }

    private func exportDiagnosticLog() {
        let log = DiagnosticLogger.shared.exportLog()
        let panel = NSSavePanel()
        panel.title = L10n("Exportar log de diagnostico")
        let dateStr: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Date())
        }()
        panel.nameFieldStringValue = "zion-diagnostic-\(dateStr).txt"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? log.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func copyDiagnosticLog() {
        let log = DiagnosticLogger.shared.exportLog()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(log, forType: .string)
    }

    private func showAboutPanel() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "Zion",
            .applicationVersion: version,
            .version: build,
        ]

        // Build credits with website link
        let credits = NSMutableAttributedString()

        let tagline = NSAttributedString(
            string: "Graph. Code. Terminal. One window.\n\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        credits.append(tagline)

        let websiteString = NSAttributedString(
            string: "zioncode.dev",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.linkColor,
                .link: URL(string: "https://zioncode.dev")!,
            ]
        )
        credits.append(websiteString)

        let madeWith = NSAttributedString(
            string: "\n\n" + L10n("about.madeWith") + "\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
        )
        credits.append(madeWith)

        // Center-align all text
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        credits.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: credits.length))

        options[.credits] = credits

        NSApp.orderFrontStandardAboutPanel(options: options)
    }
}

private extension View {
    @ViewBuilder
    func applyShortcutBinding(_ binding: ShortcutBinding?) -> some View {
        if let binding,
           let keyEquivalent = binding.key.menuKeyEquivalent {
            keyboardShortcut(keyEquivalent, modifiers: binding.modifiers.eventModifiers)
        } else {
            self
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var pendingOpenURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        let fileURLs = urls.filter { $0.isFileURL && !$0.hasDirectoryPath }
        guard !fileURLs.isEmpty else { return }
        AppDelegate.pendingOpenURLs = fileURLs
        NotificationCenter.default.post(
            name: .openFilesFromFinder,
            object: nil,
            userInfo: ["urls": fileURLs]
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "terminal.scrollbackSize": 5000,
            "terminal.bellMode": "system",
            "terminal.openHyperlinks": true,
            "terminal.copyOnSelect": false,
            "terminal.aiImageDisplay": false,
            "zion.ntfy.enabled": false,
            "zion.ntfy.localNotifications": false,
        ])

        registerFonts()
        ClipboardMonitor.purgeStaleFilesOnLaunch()
        ZionTemp.purgeStaleFiles()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClipboardMonitor.cleanupAllTempFiles()
    }

    private func registerFonts() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                print("Failed to register font: \(url.lastPathComponent) - \(error.debugDescription)")
            }
        }
    }
}
