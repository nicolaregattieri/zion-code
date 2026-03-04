#if !os(iOS) && !os(Windows)
import Foundation
@preconcurrency import SwiftTerm

/// A headless terminal that bridges process output to the remote access
/// screen update pipeline, so headless sessions push updates to mobile clients.
/// Similar to SwiftTerm's HeadlessTerminal but with an onOutput callback.
final class RemoteHeadlessTerminal: TerminalDelegate, LocalProcessDelegate {
    public private(set) var terminal: Terminal!
    public var process: LocalProcess!

    private let sessionID: UUID
    private let onOutput: @Sendable (UUID, Data) -> Void
    private let onEnd: (_ exitCode: Int32?) -> Void

    init(
        sessionID: UUID,
        onOutput: @MainActor @escaping (UUID, Data) -> Void,
        onEnd: @escaping (_ exitCode: Int32?) -> Void
    ) {
        self.sessionID = sessionID
        self.onOutput = { sid, data in
            Task { @MainActor in onOutput(sid, data) }
        }
        self.onEnd = onEnd
        terminal = Terminal(delegate: self, options: .default)
        process = LocalProcess(delegate: self, dispatchQueue: nil)
    }

    // MARK: - LocalProcessDelegate

    public func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        onEnd(exitCode)
    }

    public func dataReceived(slice: ArraySlice<UInt8>) {
        terminal.feed(buffer: slice)
        let sid = sessionID
        let data = Data(slice)
        onOutput(sid, data)
    }

    // MARK: - TerminalDelegate (send data from terminal back to process)

    public func send(source: Terminal, data: ArraySlice<UInt8>) {
        process.send(data: data)
    }

    // MARK: - Public API

    public func send(data: ArraySlice<UInt8>) {
        process.send(data: data)
    }

    public func getWindowSize() -> winsize {
        winsize(ws_row: UInt16(terminal.rows), ws_col: UInt16(terminal.cols), ws_xpixel: 16, ws_ypixel: 16)
    }

    // MARK: - TerminalDelegate stubs

    public func mouseModeChanged(source: Terminal) {}
    public func hostCurrentDirectoryUpdated(source: Terminal) {}
    public func colorChanged(source: Terminal, idx: Int) {}
}
#endif
