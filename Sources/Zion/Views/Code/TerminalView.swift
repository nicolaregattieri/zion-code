import SwiftUI
import AppKit
@preconcurrency import SwiftTerm

struct TerminalTabView: NSViewRepresentable {
    @ObservedObject var session: TerminalSession
    var theme: EditorTheme

    func makeNSView(context: Context) -> SwiftTerm.TerminalView {
        let terminalView = SwiftTerm.TerminalView(frame: .zero)
        terminalView.allowMouseReporting = true
        terminalView.terminalDelegate = context.coordinator

        applyTheme(to: terminalView)

        context.coordinator.startProcess(view: terminalView)

        return terminalView
    }

    func updateNSView(_ nsView: SwiftTerm.TerminalView, context: Context) {
        applyTheme(to: nsView)

        if session.isAlive && context.coordinator.processIsDead {
            context.coordinator.restartProcess(view: nsView)
        }
    }

    static func dismantleNSView(_ nsView: SwiftTerm.TerminalView, coordinator: Coordinator) {
        coordinator.killProcess()
    }

    private func applyTheme(to view: SwiftTerm.TerminalView) {
        let colors = theme.colors
        view.layer?.backgroundColor = colors.nsBackground.cgColor
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    class Coordinator: NSObject, SwiftTerm.TerminalViewDelegate, SwiftTerm.LocalProcessDelegate {
        var parent: TerminalTabView
        private var process: LocalProcess?
        private weak var terminalView: SwiftTerm.TerminalView?
        private(set) var processIsDead = false

        init(_ parent: TerminalTabView) {
            self.parent = parent
        }

        func startProcess(view: SwiftTerm.TerminalView) {
            self.terminalView = view
            let url = parent.session.workingDirectory

            Task {
                let process = LocalProcess(delegate: self, dispatchQueue: .main)
                self.process = process
                self.processIsDead = false

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
            }
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
                if let fd = process?.childfd {
                    let rows = UInt16(max(0, min(Int(UInt16.max), newRows)))
                    let cols = UInt16(max(0, min(Int(UInt16.max), newCols)))
                    var size = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
                    _ = PseudoTerminalHelpers.setWinSize(masterPtyDescriptor: fd, windowSize: &size)
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
