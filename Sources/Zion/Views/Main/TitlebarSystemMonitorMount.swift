import AppKit
import SwiftUI

/// Global manager that adds / removes the `TopBarSystemMonitorPill` to the
/// NSWindow title bar via `NSTitlebarAccessoryViewController`. SwiftUI-based
/// mounts (NSViewRepresentable inside `.background` / `.overlay`) failed to
/// attach reliably because the wrapper view never reached the window when
/// rendered at zero size, so this manager is driven directly by AppKit
/// notifications and the `topbar.systemMonitor.enabled` UserDefaults flag.
@MainActor
final class TitlebarSystemMonitorManager {

    static let shared = TitlebarSystemMonitorManager()

    private static let defaultsKey = "topbar.systemMonitor.enabled"
    /// One accessory per window — keyed by ObjectIdentifier so we can detach
    /// even after the window deallocates (we never dereference the key).
    private var accessories: [ObjectIdentifier: WeakAccessory] = [:]
    private var observers: [NSObjectProtocol] = []

    private struct WeakAccessory {
        weak var controller: NSTitlebarAccessoryViewController?
    }

    private init() {}

    /// Call once from `applicationDidFinishLaunching`. Hooks UserDefaults +
    /// NSWindow key / close notifications, then runs an initial sync so any
    /// already-open window picks up the accessory if the user previously had
    /// the toggle on.
    func install() {
        // No-op. Pill renders inside SwiftUI toolbar ControlGroup.
    }

    // MARK: - Sync

    private func syncAllWindows() {
        for window in NSApp.windows where window.contentView != nil {
            syncWindow(window)
        }
    }

    private func syncWindow(_ window: NSWindow) {
        guard isMainContentWindow(window) else { return }
        let enabled = UserDefaults.standard.bool(forKey: Self.defaultsKey)
        if enabled {
            attach(to: window)
        } else {
            detach(from: window)
        }
    }

    /// Filter out floating panels, sheets, popovers, etc. — only attach the
    /// pill to the primary content window (or windows that look like one).
    private func isMainContentWindow(_ window: NSWindow) -> Bool {
        guard window.styleMask.contains(.titled) else { return false }
        guard window.contentView?.frame.height ?? 0 > 200 else { return false }
        return true
    }

    private func attach(to window: NSWindow) {
        let key = ObjectIdentifier(window)
        if let existing = accessories[key]?.controller,
           window.titlebarAccessoryViewControllers.contains(existing) {
            return
        }
        let host = NSHostingController(rootView:
            TopBarSystemMonitorPill()
                .padding(.horizontal, 6)
        )
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = host.view
        accessory.layoutAttribute = .right
        accessory.fullScreenMinHeight = 28
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.setContentHuggingPriority(.required, for: .horizontal)

        window.addTitlebarAccessoryViewController(accessory)
        accessories[key] = WeakAccessory(controller: accessory)
    }

    private func detach(from window: NSWindow) {
        let key = ObjectIdentifier(window)
        guard let acc = accessories[key]?.controller else { return }
        if let idx = window.titlebarAccessoryViewControllers.firstIndex(of: acc) {
            window.removeTitlebarAccessoryViewController(at: idx)
        }
        accessories.removeValue(forKey: key)
    }
}

// MARK: - UserDefaults KVO key path

extension UserDefaults {
    @objc dynamic var topbarSystemMonitorEnabled: Bool {
        bool(forKey: "topbar.systemMonitor.enabled")
    }
}

// MARK: - SwiftUI no-op stub (kept so the existing call site in ContentView
// still compiles — the real attach happens via the manager singleton).
struct TitlebarSystemMonitorMount: View {
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
