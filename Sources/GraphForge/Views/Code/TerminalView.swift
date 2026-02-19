import SwiftUI
import AppKit
@preconcurrency import SwiftTerm

struct TerminalView: NSViewRepresentable {
    @ObservedObject var model: RepositoryViewModel
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
        var parent: TerminalView
        private var process: LocalProcess?
        private weak var terminalView: SwiftTerm.TerminalView?
        
        init(_ parent: TerminalView) {
            self.parent = parent
        }
        
        func startProcess(view: SwiftTerm.TerminalView) {
            self.terminalView = view
            let url = parent.model.repositoryURL
            
            // LocalProcess needs a non-isolated or specific queue. 
            // We use a Task to bridge.
            Task {
                guard let url = url else { return }
                
                let process = LocalProcess(delegate: self, dispatchQueue: .main)
                self.process = process
                
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
        
        // MARK: - TerminalViewDelegate
        
        nonisolated func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            Task { @MainActor in
                process?.send(data: data)
            }
        }
        
        nonisolated func scrolled(source: SwiftTerm.TerminalView, position: Double) {}
        nonisolated func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}
        nonisolated func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            Task { @MainActor in
                if let fd = process?.childfd {
                    // Clamp values to valid UInt16 range to avoid crashes
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
        
        nonisolated func processTerminated(_ source: SwiftTerm.LocalProcess, exitCode: Int32?) {}
        
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
