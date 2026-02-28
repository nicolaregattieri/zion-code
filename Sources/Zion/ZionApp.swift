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
}

@main
struct ZionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var updater = SparkleUpdater()

    var body: some Scene {
        WindowGroup {
            ContentView()
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
                Button(L10n("format.document")) {
                    NotificationCenter.default.post(name: .formatDocument, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.shift, .option])
            }

            CommandMenu(L10n("focus.menu")) {
                Button(L10n("zen.mode")) {
                    NotificationCenter.default.post(name: .toggleZenMode, object: nil)
                }
                .keyboardShortcut("j", modifiers: [.command, .control])

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
                .keyboardShortcut("/", modifiers: .command)

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
        }

        Settings {
            SettingsView()
        }
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
            "terminal.imageRendering": true,
            "terminal.copyOnSelect": false,
            "terminal.aiImageDisplay": false,
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
