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
    
    class Coordinator: NSObject, @preconcurrency SwiftTerm.TerminalViewDelegate, @preconcurrency SwiftTerm.LocalProcessDelegate {
        var parent: TerminalView
        private var process: LocalProcess?
        private weak var terminalView: SwiftTerm.TerminalView?
        
        init(_ parent: TerminalView) {
            self.parent = parent
        }
        
        func startProcess(view: SwiftTerm.TerminalView) {
            self.terminalView = view
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let url = self.parent.model.repositoryURL else { return }
                
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
        
        func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            process?.send(data: data)
        }
        
        func scrolled(source: SwiftTerm.TerminalView, position: Double) {}
        func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}
        func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            if let fd = process?.childfd {
                var size = winsize(ws_row: UInt16(newRows), ws_col: UInt16(newCols), ws_xpixel: 0, ws_ypixel: 0)
                _ = PseudoTerminalHelpers.setWinSize(masterPtyDescriptor: fd, windowSize: &size)
            }
        }
        func requestKeyboadFocus(source: SwiftTerm.TerminalView) {}
        func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
            if let str = String(data: content, encoding: .utf8) {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(str, forType: .string)
            }
        }
        func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}
        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
        
        // MARK: - LocalProcessDelegate
        
        func processTerminated(_ source: SwiftTerm.LocalProcess, exitCode: Int32?) {}
        
        func dataReceived(slice: ArraySlice<UInt8>) {
            let view = self.terminalView
            DispatchQueue.main.async {
                view?.feed(byteArray: slice)
            }
        }
        
        func getWindowSize() -> winsize {
            let view = self.terminalView
            return MainActor.assumeIsolated {
                if let terminal = view?.getTerminal() {
                    return winsize(ws_row: UInt16(terminal.rows), ws_col: UInt16(terminal.cols), ws_xpixel: 0, ws_ypixel: 0)
                }
                return winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
            }
        }
    }
}
