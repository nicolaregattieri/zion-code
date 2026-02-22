import SwiftUI
import Sparkle
import UniformTypeIdentifiers

extension Notification.Name {
    static let showKeyboardShortcuts = Notification.Name("showKeyboardShortcuts")
    static let showHelp = Notification.Name("showHelp")
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
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        registerFonts()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
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
