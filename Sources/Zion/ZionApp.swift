import SwiftUI
import Sparkle
import UniformTypeIdentifiers

extension Notification.Name {
    static let showKeyboardShortcuts = Notification.Name("showKeyboardShortcuts")
    static let showHelp = Notification.Name("showHelp")
    static let showOnboarding = Notification.Name("showOnboarding")
    static let showFeatureTour = Notification.Name("showFeatureTour")
    static let toggleZenMode = Notification.Name("toggleZenMode")
    static let toggleZionMode = Notification.Name("toggleZionMode")
    static let openFilesFromFinder = Notification.Name("openFilesFromFinder")
    static let openDirectoryFromFinder = Notification.Name("openDirectoryFromFinder")
    static let formatDocument = Notification.Name("formatDocument")
    static let formatCodeFile = Notification.Name("formatCodeFile")
    static let openMobileAccessSettings = Notification.Name("openMobileAccessSettings")
    static let openAISettings = Notification.Name("openAISettings")
    static let openEditorSettings = Notification.Name("openEditorSettings")
    static let refreshRepoMemory = Notification.Name("refreshRepoMemory")
    static let clearRepoMemory = Notification.Name("clearRepoMemory")
    static let focusCommitField = Notification.Name("focusCommitField")
    static let zionFind = Notification.Name("zionFind")
}

@main
struct ZionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var updater = SparkleUpdater()
    @StateObject private var shortcutRegistry = ShortcutRegistry.shared
    @AppStorage(UserDefaultsKeys.General.uiLanguage) private var uiLanguageRaw: String = AppLanguage.system.rawValue

    private var uiLanguage: AppLanguage { AppLanguage(rawValue: uiLanguageRaw) ?? .system }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, uiLanguage.locale)
                .onChange(of: uiLanguageRaw) { _, _ in
                    LocaleSignal.shared.bump()
                }
                .environment(updater)
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

            CommandGroup(replacing: .undoRedo) {
                Button(L10n("menu.undo")) {
                    if let model = RepositoryViewModel.activeReference.value {
                        model.performPreferredUndo()
                    } else {
                        NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                    }
                }
                .keyboardShortcut("z", modifiers: [.command])

                Button(L10n("menu.redo")) {
                    if let model = RepositoryViewModel.activeReference.value {
                        model.performPreferredRedo()
                    } else {
                        NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                    }
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
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
                .applyShortcutBinding(shortcutRegistry.binding(for: .zenMode))

                Button("Zion Mode") {
                    NotificationCenter.default.post(name: .toggleZionMode, object: nil)
                }
                .applyShortcutBinding(shortcutRegistry.binding(for: .zionMode))
            }

            CommandGroup(replacing: .help) {
                Button(L10n("Conheca o Zion")) {
                    NotificationCenter.default.post(name: .showHelp, object: nil)
                }

                Button(L10n("help.openFeatureTour")) {
                    NotificationCenter.default.post(name: .showFeatureTour, object: nil)
                }

                Divider()

                Button(L10n("Atalhos de Teclado")) {
                    NotificationCenter.default.post(name: .showKeyboardShortcuts, object: nil)
                }
                .applyShortcutBinding(shortcutRegistry.binding(for: .showKeyboardShortcuts))

                Divider()

                Button(updater.updateAvailable && updater.latestVersion != nil
                    ? "\(L10n("Buscar Atualizacoes...")) (\(updater.latestVersion!))"
                    : L10n("Buscar Atualizacoes...")
                ) {
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
            SettingsView(updater: updater)
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

extension View {
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
    @MainActor static var pendingOpenDirectoryURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        let directoryURLs = urls.filter { $0.isFileURL && $0.hasDirectoryPath }
        let fileURLs = urls.filter { $0.isFileURL && !$0.hasDirectoryPath }

        if let dirURL = directoryURLs.first {
            AppDelegate.pendingOpenDirectoryURLs = [dirURL]
            NotificationCenter.default.post(
                name: .openDirectoryFromFinder,
                object: nil,
                userInfo: ["url": dirURL]
            )
        }

        if !fileURLs.isEmpty {
            AppDelegate.pendingOpenURLs = fileURLs
            NotificationCenter.default.post(
                name: .openFilesFromFinder,
                object: nil,
                userInfo: ["urls": fileURLs]
            )
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            UserDefaultsKeys.Terminal.scrollbackSize: 10_000,
            UserDefaultsKeys.Terminal.bellMode: "system",
            UserDefaultsKeys.Terminal.openHyperlinks: true,
            UserDefaultsKeys.Terminal.copyOnSelect: false,
            UserDefaultsKeys.Terminal.aiImageDisplay: false,
            UserDefaultsKeys.Ntfy.enabled: false,
            UserDefaultsKeys.Ntfy.localNotifications: false,
        ])

        registerFonts()

        // Hosting credential migrations
        HostingCredentialStore.migrateFromUserDefaults()
        HostingAccountStore.migrateFromSingleAccount()

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
