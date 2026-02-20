import SwiftUI
import AppKit
@preconcurrency import SwiftTerm

// MARK: - TerminalTabView

struct TerminalTabView: NSViewRepresentable {
    var session: TerminalSession
    var theme: EditorTheme
    var fontSize: Double = 13.0
    var fontFamily: String = "SF Mono"
    var model: RepositoryViewModel?

    func makeNSView(context: Context) -> SwiftTerm.TerminalView {
        // Reuse cached view from session (preserves running process + display buffer)
        if let cachedView = session._cachedView as? SwiftTerm.TerminalView {
            cachedView.removeFromSuperview()
            cachedView.terminalDelegate = context.coordinator
            context.coordinator.reattach(view: cachedView)
            // Don't clear cache — reattach re-populates it for future restructures
            applyTheme(to: cachedView, context: context)
            return cachedView
        }

        // Fresh terminal
        let terminalView = SwiftTerm.TerminalView(frame: .zero)
        terminalView.allowMouseReporting = true
        terminalView.terminalDelegate = context.coordinator

        applyTheme(to: terminalView, context: context)

        // Cursor style only on initial setup (don't override shell programs in updateNSView)
        terminalView.getTerminal().setCursorStyle(.blinkBlock)

        context.coordinator.startProcess(view: terminalView)

        return terminalView
    }

    func updateNSView(_ nsView: SwiftTerm.TerminalView, context: Context) {
        applyTheme(to: nsView, context: context)

        if session.isAlive && context.coordinator.processIsDead {
            context.coordinator.restartProcess(view: nsView)
        }
    }

    static func dismantleNSView(_ nsView: SwiftTerm.TerminalView, coordinator: Coordinator) {
        // If session was explicitly killed, let everything deallocate naturally.
        guard coordinator.parent.session._shouldPreserve else { return }
        // Cache coordinator + NSView on session so they survive view tree restructuring.
        // Explicit kills happen via session.killCachedProcess() in the ViewModel.
        // Note: don't unregister send callback here — reattach() re-registers it,
        // and SwiftUI may create the new view BEFORE calling dismantle on the old one.
        coordinator.parent.session._cachedView = nsView
        coordinator.parent.session._processBridge = coordinator
    }

    private func applyTheme(to view: SwiftTerm.TerminalView, context: Context) {
        let palette = theme.terminalPalette

        // Always keep layer bg in sync (cheap — setter doesn't touch layer)
        view.layer?.backgroundColor = palette.background.cgColor

        // Only apply expensive operations when theme or font actually changes
        let fontChanged = fontSize != context.coordinator.lastAppliedFontSize
                       || fontFamily != context.coordinator.lastAppliedFontFamily
        guard theme != context.coordinator.lastAppliedTheme || fontChanged else { return }
        context.coordinator.lastAppliedTheme = theme
        context.coordinator.lastAppliedFontSize = fontSize
        context.coordinator.lastAppliedFontFamily = fontFamily

        // Base colors (must be set BEFORE installPalette — palette generation uses these)
        view.nativeForegroundColor = palette.foreground
        view.nativeBackgroundColor = palette.background

        // ANSI 16-color palette
        view.getTerminal().installPalette(colors: palette.ansiColors)

        // Cursor
        view.caretColor = palette.cursorColor
        view.caretTextColor = palette.cursorTextColor

        // Font with fallback chain
        let size = CGFloat(fontSize)
        let font = NSFont(name: fontFamily, size: size)
                  ?? NSFont(name: "Menlo", size: size)
                  ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        view.font = font

        // Force redraw — setters above don't trigger needsDisplay
        view.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        if let existing = session._processBridge as? Coordinator {
            existing.parent = self
            return existing
        }
        return Coordinator(self)
    }

    @MainActor
    class Coordinator: NSObject, SwiftTerm.TerminalViewDelegate, SwiftTerm.LocalProcessDelegate {
        var parent: TerminalTabView
        private var process: LocalProcess?
        private weak var terminalView: SwiftTerm.TerminalView?
        private(set) var processIsDead = false
        var lastAppliedTheme: EditorTheme?
        var lastAppliedFontSize: Double?
        var lastAppliedFontFamily: String?
        private var pendingResizeTask: Task<Void, Never>?

        init(_ parent: TerminalTabView) {
            self.parent = parent
        }

        // MARK: - Process lifecycle

        func startProcess(view: SwiftTerm.TerminalView) {
            self.terminalView = view
            let url = parent.session.workingDirectory
            let sessionID = parent.session.id

            Task {
                let process = LocalProcess(delegate: self, dispatchQueue: .main)
                self.process = process
                self.processIsDead = false

                // Register send callback so ClipboardDrawer can paste text into this terminal
                parent.model?.registerTerminalSendCallback(sessionID: sessionID) { [weak self] data in
                    Task { @MainActor in
                        self?.process?.send(data: ArraySlice(data))
                    }
                }

                var env = ProcessInfo.processInfo.environment
                env["TERM"] = "xterm-256color"
                env["LANG"] = "en_US.UTF-8"
                env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:" + (env["PATH"] ?? "")

                let envArray = env.map { "\($0.key)=\($0.value)" }

                process.startProcess(
                    executable: "/bin/zsh",
                    args: ["-l"],
                    environment: envArray,
                    currentDirectory: url.path
                )

                // Eagerly cache coordinator + view for reuse across view tree changes.
                // SwiftUI may create the new view BEFORE dismantling the old one (e.g. split),
                // so the cache must be populated before dismantleNSView fires.
                parent.session._cachedView = view
                parent.session._processBridge = self
                parent.session._shellPid = process.shellPid

                // Force theme re-application on next updateNSView cycle
                self.lastAppliedTheme = nil
            }
        }

        /// Reattach to a cached terminal view after view tree restructure.
        /// The coordinator (and its LocalProcess) survived via session._processBridge.
        func reattach(view: SwiftTerm.TerminalView) {
            self.terminalView = view

            // Re-cache for future restructures (split → unsplit → split again)
            parent.session._cachedView = view
            parent.session._processBridge = self

            // Re-register send callback for clipboard
            let sessionID = parent.session.id
            parent.model?.registerTerminalSendCallback(sessionID: sessionID) { [weak self] data in
                Task { @MainActor in
                    self?.process?.send(data: ArraySlice(data))
                }
            }

            // Force theme re-application
            self.lastAppliedTheme = nil
        }

        func restartProcess(view: SwiftTerm.TerminalView) {
            killProcess()
            view.getTerminal().resetToInitialState()
            startProcess(view: view)
        }

        func killProcess() {
            if let pid = process?.shellPid, pid > 0 {
                kill(pid, SIGTERM)
            }
            process = nil
            parent.session._shellPid = 0
            parent.model?.unregisterTerminalSendCallback(sessionID: parent.session.id)
        }

        // MARK: - TerminalViewDelegate

        nonisolated func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            Task { @MainActor in
                process?.send(data: data)
            }
        }

        nonisolated func scrolled(source: SwiftTerm.TerminalView, position: Double) {}
        nonisolated func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {
            Task { @MainActor in
                parent.session.title = title.isEmpty ? parent.session.label : compactTitle(from: title)
            }
        }

        @MainActor
        private func compactTitle(from title: String) -> String {
            // Parse "user@host:~/path/to/folder" -> "folder"
            if let colonIndex = title.firstIndex(of: ":") {
                let pathPart = String(title[title.index(after: colonIndex)...])
                let cleaned = pathPart.trimmingCharacters(in: .whitespaces)
                if cleaned == "~" { return "~" }
                if let last = cleaned.split(separator: "/").last {
                    return String(last)
                }
                return cleaned
            }
            // Fallback: if it looks like a path, take the last component
            if title.contains("/") {
                if let last = title.split(separator: "/").last {
                    return String(last)
                }
            }
            return title
        }
        nonisolated func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            Task { @MainActor in
                // Cancel any pending resize — only the final size matters
                pendingResizeTask?.cancel()

                // Skip degenerate sizes (terminal hidden or mid-animation)
                guard newRows > 0, newCols > 0 else { return }

                pendingResizeTask = Task {
                    try? await Task.sleep(for: .milliseconds(80))
                    guard !Task.isCancelled else { return }

                    if let fd = process?.childfd {
                        let rows = UInt16(max(1, min(Int(UInt16.max), newRows)))
                        let cols = UInt16(max(1, min(Int(UInt16.max), newCols)))
                        var size = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
                        _ = PseudoTerminalHelpers.setWinSize(masterPtyDescriptor: fd, windowSize: &size)
                    }
                }
            }
        }
        nonisolated func requestKeyboadFocus(source: SwiftTerm.TerminalView) {}
        nonisolated func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
            if let str = String(data: content, encoding: .utf8) {
                DispatchQueue.main.async {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(str, forType: .string)
                }
            }
        }
        nonisolated func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}
        nonisolated func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}

        // MARK: - LocalProcessDelegate

        nonisolated func processTerminated(_ source: SwiftTerm.LocalProcess, exitCode: Int32?) {
            Task { @MainActor in
                processIsDead = true
                parent.session.isAlive = false
            }
        }

        nonisolated func dataReceived(slice: ArraySlice<UInt8>) {
            Task { @MainActor in
                terminalView?.feed(byteArray: slice)
            }
        }

        nonisolated func getWindowSize() -> winsize {
            MainActor.assumeIsolated {
                if let terminal = terminalView?.getTerminal() {
                    let rows = UInt16(max(0, min(Int(UInt16.max), terminal.rows)))
                    let cols = UInt16(max(0, min(Int(UInt16.max), terminal.cols)))
                    return winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
                }
                return winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
            }
        }
    }
}
