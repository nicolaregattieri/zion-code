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
    var transparentBackground: Bool = false

    private static let log = DiagnosticLogger.shared

    func makeNSView(context: Context) -> SwiftTerm.TerminalView {
        // Reuse cached view from session (preserves running process + display buffer)
        if let cachedView = session._cachedView as? SwiftTerm.TerminalView {
            Self.log.log(.info, "makeNSView CACHED", context: "\(session.label)(\(session.id.uuidString.prefix(4))) alive=\(session.isAlive) preserve=\(session._shouldPreserve) pid=\(session._shellPid)", source: "TerminalTabView")
            cachedView.removeFromSuperview()
            cachedView.terminalDelegate = context.coordinator
            applyInteractionPolicy(to: cachedView)
            if let zionView = cachedView as? ZionTerminalView {
                zionView.onDropActivated = { [coordinator = context.coordinator] in
                    coordinator.prepareForFileDrop()
                }
                zionView.onFileDrop = { [coordinator = context.coordinator] text in
                    coordinator.handleFileDrop(text)
                }
            }
            context.coordinator.reattach(view: cachedView)
            // Don't clear cache — reattach re-populates it for future restructures
            applyTheme(to: cachedView, context: context)
            // Hide SwiftTerm's legacy scroller (we don't need a visible scrollbar)
            for subview in cachedView.subviews where subview is NSScroller {
                subview.isHidden = true
            }
            return cachedView
        }

        Self.log.log(.info, "makeNSView FRESH", context: "\(session.label)(\(session.id.uuidString.prefix(4)))", source: "TerminalTabView")
        // Fresh terminal (ZionTerminalView adds Finder drag-and-drop support)
        let terminalView = ZionTerminalView(frame: .zero)
        terminalView.onDropActivated = { [coordinator = context.coordinator] in
            coordinator.prepareForFileDrop()
        }
        terminalView.onFileDrop = { [coordinator = context.coordinator] text in
            coordinator.handleFileDrop(text)
        }
        applyInteractionPolicy(to: terminalView)
        terminalView.terminalDelegate = context.coordinator

        // Apply custom terminal options BEFORE theme — applyCustomOptions replaces the
        // Terminal instance with default colors, so theme must come after.
        let scrollback = UserDefaults.standard.integer(forKey: UserDefaultsKeys.Terminal.scrollbackSize)
        var opts = SwiftTerm.TerminalOptions()
        opts.scrollback = scrollback == Int.max ? Int.max : max(100, scrollback)
        opts.enableSixelReported = true
        terminalView.applyCustomOptions(opts)

        applyTheme(to: terminalView, context: context)

        // Cursor style only on initial setup (don't override shell programs in updateNSView)
        terminalView.getTerminal().setCursorStyle(.blinkBlock)

        context.coordinator.startProcess(view: terminalView)

        // Hide SwiftTerm's legacy scroller (we don't need a visible scrollbar)
        for subview in terminalView.subviews where subview is NSScroller {
            subview.isHidden = true
        }
        return terminalView
    }

    func updateNSView(_ nsView: SwiftTerm.TerminalView, context: Context) {
        applyTheme(to: nsView, context: context)
        applyInteractionPolicy(to: nsView)

        // Read isAlive for @Observable tracking (processTerminated changes it,
        // which triggers this updateNSView call)
        let _ = session.isAlive

        // Auto-restart dead processes for preserved sessions.
        // Uses _shouldPreserve (not isAlive) to avoid race with async processTerminated callback.
        if context.coordinator.processIsDead && session._shouldPreserve {
            Self.log.log(.info, "updateNSView RESTART", context: "\(session.label)(\(session.id.uuidString.prefix(4))) dead=\(context.coordinator.processIsDead) preserve=\(session._shouldPreserve) alive=\(session.isAlive)", source: "TerminalTabView")
            session.isAlive = true
            context.coordinator.restartProcess(view: nsView)
        }
    }

    static func dismantleNSView(_ nsView: SwiftTerm.TerminalView, coordinator: Coordinator) {
        let s = coordinator.parent.session
        let isCurrentOwner = s._activeCoordinatorGeneration == coordinator.generationID
        log.log(.info, "dismantleNSView", context: "\(s.label)(\(s.id.uuidString.prefix(4))) gen=\(coordinator.shortGeneration) current=\(isCurrentOwner) preserve=\(s._shouldPreserve) alive=\(s.isAlive) pid=\(s._shellPid)", source: "TerminalTabView")
        // If session was explicitly killed, let everything deallocate naturally.
        guard s._shouldPreserve else { return }
        // The active owner is bound during startProcess/reattach. We intentionally
        // avoid writing cache ownership here to prevent stale dismantle calls
        // from clobbering a newer live coordinator/view pair.
        // If we are no longer the active owner (view replaced by reattach), remove our
        // monitors now — killProcess won't be called for us and orphaned global NSEvent
        // monitors accumulate overhead on every app-wide mouse/keyboard event.
        if !isCurrentOwner {
            coordinator.removeShiftEnterMonitor()
            coordinator.removeMouseInteractionMonitors()
            coordinator.removeFreezeResetObserver()
        }
    }

    private func applyTheme(to view: SwiftTerm.TerminalView, context: Context) {
        let palette = theme.terminalPalette

        // Transparent background for Ghostty-style terminal (Zion + Zen mode)
        if transparentBackground {
            view.layer?.backgroundColor = NSColor.clear.cgColor
            view.layer?.isOpaque = false
        } else {
            view.layer?.backgroundColor = palette.background.cgColor
            view.layer?.isOpaque = true
        }

        // Only apply expensive operations when theme or font actually changes
        let fontChanged = fontSize != context.coordinator.lastAppliedFontSize
                       || fontFamily != context.coordinator.lastAppliedFontFamily
        let transparencyChanged = transparentBackground != context.coordinator.lastAppliedTransparent
        guard theme != context.coordinator.lastAppliedTheme || fontChanged || transparencyChanged else { return }
        context.coordinator.lastAppliedTheme = theme
        context.coordinator.lastAppliedFontSize = fontSize
        context.coordinator.lastAppliedFontFamily = fontFamily
        context.coordinator.lastAppliedTransparent = transparentBackground

        // Base colors (must be set BEFORE installPalette — palette generation uses these)
        view.nativeForegroundColor = palette.foreground
        view.nativeBackgroundColor = transparentBackground ? NSColor.clear : palette.background

        // ANSI 16-color palette (installColors clears attributed-string caches + forces full redraw)
        view.installColors(palette.ansiColors)

        // Cursor
        view.caretColor = palette.cursorColor
        view.caretTextColor = palette.cursorTextColor

        // Font with fallback chain
        let size = CGFloat(fontSize)
        let resolvedFont = MonospaceFontResolver.resolve(name: fontFamily, size: size)
        view.font = resolvedFont.font

        // Force redraw — setters above don't trigger needsDisplay
        view.needsDisplay = true
    }

    private func applyInteractionPolicy(to view: SwiftTerm.TerminalView) {
        // Keep mouse reporting available for TUIs while still allowing users to
        // drag-select terminal text even when applications enable mouse tracking.
        view.allowMouseReporting = true
        view.prioritizeSelectionInteraction = true
    }

    func makeCoordinator() -> Coordinator {
        if let existing = session._processBridge as? Coordinator {
            existing.parent = self
            return existing
        }
        return Coordinator(self)
    }

    static func syncInstalledTerminalHelpersForCurrentSettings() {
        let defaults = UserDefaults.standard
        Coordinator.installScripts(
            aiImageDisplay: defaults.bool(forKey: UserDefaultsKeys.Terminal.aiImageDisplay)
        )
    }

    @MainActor
    class Coordinator: NSObject, SwiftTerm.TerminalViewDelegate, SwiftTerm.LocalProcessDelegate {
        var parent: TerminalTabView
        let generationID = UUID()
        private var process: LocalProcess?
        private weak var terminalView: SwiftTerm.TerminalView?
        private(set) var processIsDead = false
        var lastAppliedTheme: EditorTheme?
        var lastAppliedFontSize: Double?
        var lastAppliedFontFamily: String?
        var lastAppliedTransparent: Bool = false
        private var pendingResizeTask: Task<Void, Never>?
        private var shiftEnterMonitor: Any?
        private var keyDownMonitor: Any?
        private var mouseDownMonitor: Any?
        private var mouseDragMonitor: Any?
        private var mouseUpMonitor: Any?
        private var scrollWheelMonitor: Any?
        private var pendingTerminalOutput = Data()
        private var pointerDownInTerminal = false
        private var dragSelectionFreezeActive = false
        private var persistentSelectionFreezeActive = false
        private var manualScrollFreezeActive = false
        private var manualScrollFreezeIntentActive = false
        private var preciseScrollLineAccumulator: CGFloat = 0
        private var resignActiveObserver: Any?
        private weak var outputCoordinator: TerminalOutputCoordinator?
        private static let maxBufferedOutputDuringDragSelection = 1_048_576
        private static let forcedFlushChunkBytes = 65_536

        init(_ parent: TerminalTabView) {
            self.parent = parent
        }

        var shortGeneration: String {
            String(generationID.uuidString.prefix(4))
        }

        private func bindAsCurrentOwner(view: SwiftTerm.TerminalView, shellPid: Int32? = nil) {
            let session = parent.session
            session._cachedView = view
            session._cachedTerminal = view.getTerminal()
            session._processBridge = self
            session._activeCoordinatorGeneration = generationID
            if let shellPid {
                session._shellPid = shellPid
            }
            DiagnosticLogger.shared.log(
                .info,
                "terminal.bindOwner",
                context: "\(session.label)(\(session.id.uuidString.prefix(4))) gen=\(shortGeneration) pid=\(session._shellPid)",
                source: "TerminalTabView"
            )
        }

        private func isCurrentOwner() -> Bool {
            parent.session._activeCoordinatorGeneration == generationID
        }

        static func shouldRecoverOwnerBinding(isCurrentOwner: Bool, bridgeMatchesCoordinator: Bool) -> Bool {
            !isCurrentOwner && bridgeMatchesCoordinator
        }

        static func shouldStartDragFreeze(
            isPointerDownInTerminal: Bool,
            isTerminalFocused: Bool,
            allowMouseReporting: Bool,
            prioritizeSelectionInteraction: Bool
        ) -> Bool {
            isPointerDownInTerminal && isTerminalFocused && allowMouseReporting && prioritizeSelectionInteraction
        }

        static func shouldForceFlushWhileDragFrozen(
            bufferedByteCount: Int,
            maxBufferedBytes: Int
        ) -> Bool {
            bufferedByteCount >= maxBufferedBytes
        }

        static func shouldKeepSelectionFreezeAfterMouseUp(hasSelection: Bool) -> Bool {
            hasSelection
        }

        static func shouldReleasePersistentSelectionFreezeOnMouseDown(hasPersistentSelectionFreeze: Bool) -> Bool {
            hasPersistentSelectionFreeze
        }

        static func shouldReleasePersistentSelectionFreezeOnKeyDown(
            hasPersistentSelectionFreeze: Bool,
            hasCommandModifier: Bool
        ) -> Bool {
            hasPersistentSelectionFreeze && !hasCommandModifier
        }

        static func shouldConsumePreciseScroll(
            hasPreciseScrollingDeltas: Bool,
            isTerminalFocused: Bool,
            hoveredTerminalMatches: Bool,
            canTerminalScroll: Bool
        ) -> Bool {
            hasPreciseScrollingDeltas && isTerminalFocused && hoveredTerminalMatches && canTerminalScroll
        }

        func ensureOwnerBinding(reason: String) {
            guard parent.session._shouldPreserve else { return }
            guard let liveView = terminalView ?? (parent.session._cachedView as? SwiftTerm.TerminalView) else { return }
            if !isCurrentOwner() {
                DiagnosticLogger.shared.log(
                    .info,
                    "terminal.rebindOwner",
                    context: "\(parent.session.label)(\(parent.session.id.uuidString.prefix(4))) reason=\(reason) gen=\(shortGeneration)",
                    source: "TerminalTabView"
                )
                bindAsCurrentOwner(view: liveView)
            }
        }

        // MARK: - Process lifecycle

        func startProcess(view: SwiftTerm.TerminalView) {
            self.terminalView = view
            installShiftEnterMonitor()
            installMouseInteractionMonitors()
            installFreezeResetObserver()
            let url = parent.session.workingDirectory
            let sessionID = parent.session.id

            Task {
                let process = LocalProcess(delegate: self, dispatchQueue: .main)
                self.process = process
                self.processIsDead = false

                // Register send callback so ClipboardDrawer can paste text into this terminal
                parent.model?.registerTerminalSendCallback(sessionID: sessionID) { [weak self] data in
                    self?.process?.send(data: ArraySlice(data))
                }

                var env = ProcessInfo.processInfo.environment
                env["TERM"] = "xterm-256color"
                env["COLORTERM"] = "truecolor"
                env["TERM_PROGRAM"] = "Zion"
                env["TERM_PROGRAM_VERSION"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                env["LANG"] = "en_US.UTF-8"
                env["PATH"] = "\(Self.zionBinDir):/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:" + (env["PATH"] ?? "")

                let aiImageDisplay = UserDefaults.standard.bool(forKey: UserDefaultsKeys.Terminal.aiImageDisplay)
                if aiImageDisplay {
                    env["ZION_IMAGE_DISPLAY"] = "1"
                }

                // Install standalone scripts to ~/.zion/bin/
                if aiImageDisplay {
                    Self.installScripts(
                        aiImageDisplay: aiImageDisplay
                    )
                }

                let envArray = env.map { "\($0.key)=\($0.value)" }

                // Launch via wrapper that exports ZION_TTY=$(tty) so child processes
                // (e.g. Claude Code's Bash) can write escape sequences to the pty
                // even when /dev/tty isn't available.
                process.startProcess(
                    executable: "/bin/zsh",
                    args: ["-c", "export ZION_TTY=$(tty); exec /bin/zsh -l"],
                    environment: envArray,
                    currentDirectory: url.path
                )

                // Eagerly bind live ownership before any possible stale dismantle callback.
                bindAsCurrentOwner(view: view, shellPid: process.shellPid)

                // Force theme re-application on next updateNSView cycle
                self.lastAppliedTheme = nil

                // Register with centralized output coordinator
                self.registerWithOutputCoordinator()
            }
        }

        /// Reattach to a cached terminal view after view tree restructure.
        /// The coordinator (and its LocalProcess) survived via session._processBridge.
        func reattach(view: SwiftTerm.TerminalView) {
            self.terminalView = view
            installShiftEnterMonitor()
            installMouseInteractionMonitors()
            installFreezeResetObserver()
            if process != nil {
                processIsDead = false
                parent.session.isAlive = true
            }

            // Re-wire file drop handler for Finder drag-and-drop
            if let zionView = view as? ZionTerminalView {
                zionView.onDropActivated = { [weak self] in
                    self?.prepareForFileDrop()
                }
                zionView.onFileDrop = { [weak self] text in
                    self?.handleFileDrop(text)
                }
            }

            // Re-cache for future restructures (split → unsplit → split again)
            bindAsCurrentOwner(view: view)

            // Re-register send callback for clipboard
            let sessionID = parent.session.id
            parent.model?.registerTerminalSendCallback(sessionID: sessionID) { [weak self] data in
                self?.process?.send(data: ArraySlice(data))
            }

            // Force theme re-application
            self.lastAppliedTheme = nil

            // Re-register with centralized output coordinator
            registerWithOutputCoordinator()
        }

        func restartProcess(view: SwiftTerm.TerminalView) {
            // Reset synchronously to prevent double-fire from updateNSView
            // (startProcess sets it inside a Task, leaving a window for re-entry)
            processIsDead = false
            killProcess()
            view.getTerminal().resetToInitialState()
            startProcess(view: view)
        }

        func killProcess() {
            if let pid = process?.shellPid, pid > 0 {
                kill(pid, SIGTERM)
            }
            process = nil
            removeShiftEnterMonitor()
            removeMouseInteractionMonitors()
            removeFreezeResetObserver()
            unregisterFromOutputCoordinator()
            pendingTerminalOutput.removeAll(keepingCapacity: false)
            pointerDownInTerminal = false
            dragSelectionFreezeActive = false
            persistentSelectionFreezeActive = false
            manualScrollFreezeActive = false
            manualScrollFreezeIntentActive = false
            parent.session._shellPid = 0
            if isCurrentOwner() {
                parent.session._processBridge = nil
                parent.session._activeCoordinatorGeneration = nil
            }
            parent.model?.unregisterTerminalSendCallback(sessionID: parent.session.id)
        }

        func insertSoftLineBreak() {
            let newline: [UInt8] = [0x0A]  // LF
            process?.send(data: ArraySlice(newline))
        }

        func sendText(_ text: String) {
            guard let data = text.data(using: .utf8) else { return }
            process?.send(data: ArraySlice(data))
        }

        func prepareForFileDrop() {
            ensureOwnerBinding(reason: "fileDrop")
            parent.model?.activateTerminalSession(parent.session)
            if let view = terminalView {
                view.window?.makeFirstResponder(view)
            }
        }

        func handleFileDrop(_ text: String) {
            prepareForFileDrop()
            sendText(text)
        }

        private func installShiftEnterMonitor() {
            guard shiftEnterMonitor == nil else { return }
            shiftEnterMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                guard self.isShiftReturn(event), self.isTerminalFocused else { return event }
                self.insertSoftLineBreak()
                return nil
            }
        }

        fileprivate func removeShiftEnterMonitor() {
            if let monitor = shiftEnterMonitor {
                NSEvent.removeMonitor(monitor)
                shiftEnterMonitor = nil
            }
        }

        private func installMouseInteractionMonitors() {
            if keyDownMonitor == nil {
                keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self else { return event }
                    if Self.shouldReleasePersistentSelectionFreezeOnKeyDown(
                        hasPersistentSelectionFreeze: self.persistentSelectionFreezeActive,
                        hasCommandModifier: event.modifierFlags.contains(.command)
                    ) {
                        self.releasePersistentSelectionFreezeIfNeeded(flushImmediately: true)
                    }
                    return event
                }
            }

            if mouseDownMonitor == nil {
                mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                    guard let self else { return event }
                    if Self.shouldReleasePersistentSelectionFreezeOnMouseDown(
                        hasPersistentSelectionFreeze: self.persistentSelectionFreezeActive
                    ) {
                        self.releasePersistentSelectionFreezeIfNeeded(flushImmediately: true)
                    }
                    guard self.isTerminalFocused else { return event }
                    self.pointerDownInTerminal = true
                    return event
                }
            }

            if mouseDragMonitor == nil {
                mouseDragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
                    guard let self else { return event }
                    self.beginDragSelectionFreezeIfNeeded()
                    return event
                }
            }

            guard mouseUpMonitor == nil else { return }
            mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                guard let self else { return event }
                defer {
                    self.pointerDownInTerminal = false
                    self.persistOrEndSelectionFreezeIfNeeded()
                }

                guard self.isTerminalFocused else { return event }
                guard UserDefaults.standard.bool(forKey: UserDefaultsKeys.Terminal.copyOnSelect) else { return event }
                guard let view = self.terminalView, view.selectedRange().length > 0 else { return event }
                view.copy(self)
                return event
            }

            guard scrollWheelMonitor == nil else { return }
            scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                defer { self.resetPreciseScrollAccumulatorIfNeeded(for: event) }

                guard let view = self.terminalView as? ZionTerminalView else {
                    self.preciseScrollLineAccumulator = 0
                    return event
                }

                let hoveredTerminal = ZionTerminalView.terminal(
                    atWindowPoint: event.locationInWindow,
                    in: event.window ?? view.window
                )
                let shouldConsumeScroll = Self.shouldConsumePreciseScroll(
                    hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas,
                    isTerminalFocused: self.isTerminalFocused,
                    hoveredTerminalMatches: hoveredTerminal === view,
                    canTerminalScroll: view.canScroll
                )
                guard shouldConsumeScroll else {
                    self.preciseScrollLineAccumulator = 0
                    self.finishManualScrollFreezeGestureIfNeeded(for: view)
                    return event
                }

                self.beginManualScrollFreezeIntentIfNeeded(for: view, event: event)

                let lineHeight = ZionTerminalView.preciseScrollLineHeight(
                    viewHeight: view.bounds.height,
                    terminalRows: view.getTerminal().rows
                )
                let step = ZionTerminalView.accumulatePreciseScrollStep(
                    accumulator: self.preciseScrollLineAccumulator,
                    deltaY: event.scrollingDeltaY,
                    lineHeight: lineHeight
                )
                self.preciseScrollLineAccumulator = step.remainder

                if step.lines != 0 {
                    view.applyDiscreteScroll(lines: step.lines)
                    self.syncManualScrollFreezeState(for: view)
                }
                return nil
            }
        }

        fileprivate func removeMouseInteractionMonitors() {
            if let monitor = keyDownMonitor {
                NSEvent.removeMonitor(monitor)
                keyDownMonitor = nil
            }
            if let monitor = mouseDownMonitor {
                NSEvent.removeMonitor(monitor)
                mouseDownMonitor = nil
            }
            if let monitor = mouseDragMonitor {
                NSEvent.removeMonitor(monitor)
                mouseDragMonitor = nil
            }
            if let monitor = mouseUpMonitor {
                NSEvent.removeMonitor(monitor)
                mouseUpMonitor = nil
            }
            if let monitor = scrollWheelMonitor {
                NSEvent.removeMonitor(monitor)
                scrollWheelMonitor = nil
            }
            preciseScrollLineAccumulator = 0
        }

        private func installFreezeResetObserver() {
            guard resignActiveObserver == nil else { return }
            resignActiveObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.dragSelectionFreezeActive = false
                    self.persistentSelectionFreezeActive = false
                    self.manualScrollFreezeActive = false
                    self.manualScrollFreezeIntentActive = false
                    self.preciseScrollLineAccumulator = 0
                    self.flushPendingTerminalOutput(force: true)
                }
            }
        }

        fileprivate func removeFreezeResetObserver() {
            if let obs = resignActiveObserver {
                NotificationCenter.default.removeObserver(obs)
                resignActiveObserver = nil
            }
        }

        private var isSelectionOutputFrozen: Bool {
            dragSelectionFreezeActive || persistentSelectionFreezeActive
        }

        private var isTerminalOutputFrozen: Bool {
            isSelectionOutputFrozen || manualScrollFreezeActive || manualScrollFreezeIntentActive
        }

        private func resetPreciseScrollAccumulatorIfNeeded(for event: NSEvent) {
            if ZionTerminalView.shouldResetPreciseScrollAccumulator(
                phase: event.phase,
                momentumPhase: event.momentumPhase
            ) {
                preciseScrollLineAccumulator = 0
                if let view = terminalView as? ZionTerminalView {
                    finishManualScrollFreezeGestureIfNeeded(for: view)
                }
            }
        }

        private func beginManualScrollFreezeIntentIfNeeded(for view: ZionTerminalView, event: NSEvent) {
            guard !manualScrollFreezeActive else { return }
            guard ZionTerminalView.shouldStartManualScrollFreezeIntent(
                scrollingDeltaY: event.scrollingDeltaY,
                scrollPosition: view.scrollPosition,
                canScroll: view.canScroll
            ) else { return }
            manualScrollFreezeIntentActive = true
        }

        private func syncManualScrollFreezeState(for view: SwiftTerm.TerminalView) {
            let shouldFreeze = ZionTerminalView.shouldKeepManualScrollFreeze(
                scrollPosition: view.scrollPosition,
                canScroll: view.canScroll
            )

            manualScrollFreezeIntentActive = false
            manualScrollFreezeActive = shouldFreeze

            if !shouldFreeze {
                flushPendingTerminalOutput(force: true)
            }
        }

        private func finishManualScrollFreezeGestureIfNeeded(for view: ZionTerminalView) {
            guard manualScrollFreezeIntentActive else { return }
            manualScrollFreezeIntentActive = false
            if !ZionTerminalView.shouldKeepManualScrollFreeze(
                scrollPosition: view.scrollPosition,
                canScroll: view.canScroll
            ) {
                flushPendingTerminalOutput(force: true)
            }
        }

        private func beginDragSelectionFreezeIfNeeded() {
            guard let view = terminalView else { return }
            guard Self.shouldStartDragFreeze(
                isPointerDownInTerminal: pointerDownInTerminal,
                isTerminalFocused: isTerminalFocused,
                allowMouseReporting: view.allowMouseReporting,
                prioritizeSelectionInteraction: view.prioritizeSelectionInteraction
            ) else { return }
            persistentSelectionFreezeActive = false
            dragSelectionFreezeActive = true
        }

        private func endDragSelectionFreezeIfNeeded() {
            guard dragSelectionFreezeActive else { return }
            dragSelectionFreezeActive = false
            flushPendingTerminalOutput(force: true)
        }

        private func persistOrEndSelectionFreezeIfNeeded() {
            guard dragSelectionFreezeActive || persistentSelectionFreezeActive else { return }
            let hasSelection = terminalView?.selectionActive == true
            if dragSelectionFreezeActive,
               Self.shouldKeepSelectionFreezeAfterMouseUp(hasSelection: hasSelection) {
                dragSelectionFreezeActive = false
                persistentSelectionFreezeActive = true
                return
            }

            releasePersistentSelectionFreezeIfNeeded(flushImmediately: false)
            endDragSelectionFreezeIfNeeded()
        }

        private func releasePersistentSelectionFreezeIfNeeded(flushImmediately: Bool) {
            guard persistentSelectionFreezeActive else { return }
            persistentSelectionFreezeActive = false
            if flushImmediately {
                flushPendingTerminalOutput(force: true)
            }
        }

        private func queueTerminalOutput(_ slice: ArraySlice<UInt8>) {
            guard !slice.isEmpty else { return }
            pendingTerminalOutput.append(contentsOf: slice)

            if isTerminalOutputFrozen {
                if isSelectionOutputFrozen, Self.shouldForceFlushWhileDragFrozen(
                    bufferedByteCount: pendingTerminalOutput.count,
                    maxBufferedBytes: Self.maxBufferedOutputDuringDragSelection
                ) {
                    persistentSelectionFreezeActive = false
                    dragSelectionFreezeActive = false
                    flushPendingTerminalOutput(force: true)
                }
                return
            }

            outputCoordinator?.notifyDataAvailable()
        }

        // MARK: - Output Coordinator Integration

        fileprivate func registerWithOutputCoordinator() {
            guard let coordinator = parent.model?.terminalOutputCoordinator else { return }
            outputCoordinator = coordinator
            let sessionID = parent.session.id
            coordinator.register(sessionID: sessionID, coordinator: self) { [weak self] budget in
                self?.flushWithBudget(budget) ?? false
            }
        }

        fileprivate func unregisterFromOutputCoordinator() {
            outputCoordinator?.unregister(sessionID: parent.session.id)
            outputCoordinator = nil
        }

        /// Called by the centralized output coordinator with a byte budget.
        /// Returns true if there is still pending data after this flush.
        private func flushWithBudget(_ maxBytes: Int) -> Bool {
            guard !pendingTerminalOutput.isEmpty else { return false }
            guard !isTerminalOutputFrozen else { return true }

            if terminalView == nil, let rebound = parent.session._cachedView as? SwiftTerm.TerminalView {
                terminalView = rebound
            }
            guard let view = terminalView else { return false }

            let payload: Data
            if pendingTerminalOutput.count > maxBytes {
                payload = pendingTerminalOutput.prefix(maxBytes)
                pendingTerminalOutput.removeFirst(maxBytes)
            } else {
                payload = pendingTerminalOutput
                pendingTerminalOutput.removeAll(keepingCapacity: true)
            }
            let bytes = Array(payload)
            view.feed(byteArray: bytes[...])
            parent.model?.notifyTerminalOutput(sessionID: parent.session.id, data: payload)

            return !pendingTerminalOutput.isEmpty
        }

        /// Force-flush for freeze release, process termination, etc.
        /// Bypasses the coordinator -- flushes immediately on the main thread.
        private func flushPendingTerminalOutput(force: Bool = false) {
            guard !pendingTerminalOutput.isEmpty else { return }
            guard force || !isTerminalOutputFrozen else { return }

            if terminalView == nil, let rebound = parent.session._cachedView as? SwiftTerm.TerminalView {
                terminalView = rebound
            }
            guard let view = terminalView else { return }

            let payload: Data
            if force && pendingTerminalOutput.count > Self.forcedFlushChunkBytes {
                payload = pendingTerminalOutput.prefix(Self.forcedFlushChunkBytes)
                pendingTerminalOutput.removeFirst(Self.forcedFlushChunkBytes)
            } else {
                payload = pendingTerminalOutput
                pendingTerminalOutput.removeAll(keepingCapacity: true)
            }
            let bytes = Array(payload)
            view.feed(byteArray: bytes[...])
            parent.model?.notifyTerminalOutput(sessionID: parent.session.id, data: payload)

            if !pendingTerminalOutput.isEmpty, !isTerminalOutputFrozen {
                outputCoordinator?.notifyDataAvailable()
            }
        }

        private func isShiftReturn(_ event: NSEvent) -> Bool {
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let isReturn = event.keyCode == 36 || event.keyCode == 76
            return isReturn && flags == .shift
        }

        private var isTerminalFocused: Bool {
            guard let terminalView,
                  let window = terminalView.window,
                  let firstResponder = window.firstResponder as? NSView else { return false }
            return firstResponder === terminalView || firstResponder.isDescendant(of: terminalView)
        }

        // MARK: - TerminalViewDelegate

        nonisolated func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            Task { @MainActor in
                process?.send(data: data)
            }
        }

        nonisolated func scrolled(source: SwiftTerm.TerminalView, position: Double) {
            Task { @MainActor in
                guard source === self.terminalView else { return }
                self.syncManualScrollFreezeState(for: source)
            }
        }
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

        nonisolated func bell(source: SwiftTerm.TerminalView) {
            let mode = UserDefaults.standard.string(forKey: UserDefaultsKeys.Terminal.bellMode) ?? "system"
            switch mode {
            case "off":
                break
            case "visual":
                DispatchQueue.main.async {
                    guard let layer = source.layer else { return }
                    let flash = CALayer()
                    flash.frame = layer.bounds
                    flash.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
                    layer.addSublayer(flash)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        flash.removeFromSuperlayer()
                    }
                }
            default:
                NSSound.beep()
            }
        }

        nonisolated func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {
            guard UserDefaults.standard.bool(forKey: UserDefaultsKeys.Terminal.openHyperlinks) else { return }

            let trimmedLink = link
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'<>[](){}"))

            Task { @MainActor [weak self] in
                guard let self else { return }
                let repoURL = parent.model?.repositoryURL

                if let resolved = resolveLocalLink(from: trimmedLink, repositoryURL: repoURL) {
                    let fileURL = URL(fileURLWithPath: resolved.path)
                    let isEditable = EditorFileInspector.isTextFile(fileURL)
                        || EditorFileInspector.contentKind(for: fileURL) == .markdown

                    if isEditable, let model = parent.model {
                        model.openExternalFiles([fileURL])
                        if let line = resolved.line {
                            model.editorJumpLineTarget = line
                            model.editorJumpToken += 1
                        }
                    } else {
                        NSWorkspace.shared.open(fileURL)
                    }
                    return
                }

                if let fixedup = trimmedLink.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                    if let url = NSURLComponents(string: fixedup) {
                        if let actualUrl = url.url {
                            NSWorkspace.shared.open(actualUrl)
                        }
                    }
                }
            }
        }

        private struct ResolvedLink {
            let path: String
            let line: Int?
            let column: Int?
        }

        private nonisolated func resolveLocalLink(from link: String, repositoryURL: URL?) -> ResolvedLink? {
            guard !link.isEmpty else { return nil }
            let lowercased = link.lowercased()
            let fileManager = FileManager.default

            var path: String
            if lowercased.hasPrefix("file://"), let fileURL = URL(string: link), fileURL.isFileURL {
                path = fileURL.path
            } else if link.hasPrefix("/") || link.hasPrefix("~/") {
                path = (link as NSString).expandingTildeInPath
            } else if let repositoryURL {
                path = repositoryURL.appendingPathComponent(link).path
            } else {
                return nil
            }

            if fileManager.fileExists(atPath: path) {
                return ResolvedLink(path: path, line: nil, column: nil)
            }

            if let (stripped, line, column) = extractLineColumn(from: path) {
                if fileManager.fileExists(atPath: stripped) {
                    return ResolvedLink(path: stripped, line: line, column: column)
                }
            }

            // Try resolving the raw link against repo after stripping line:col
            if let repositoryURL, !link.hasPrefix("/") && !link.hasPrefix("~/") && !lowercased.hasPrefix("file://") {
                if let (strippedLink, line, column) = extractLineColumn(from: link) {
                    let repoPath = repositoryURL.appendingPathComponent(strippedLink).path
                    if fileManager.fileExists(atPath: repoPath) {
                        return ResolvedLink(path: repoPath, line: line, column: column)
                    }
                }
            }

            return nil
        }

        private nonisolated func extractLineColumn(from path: String) -> (path: String, line: Int, column: Int?)? {
            guard let suffixRange = path.range(of: #":(\d+)(?::(\d+))?$"#, options: .regularExpression) else {
                return nil
            }
            let suffix = String(path[suffixRange]).dropFirst() // drop leading ":"
            let parts = suffix.split(separator: ":")
            guard let line = Int(parts[0]), line > 0 else { return nil }
            let column = parts.count > 1 ? Int(parts[1]) : nil
            let stripped = String(path[..<suffixRange.lowerBound])
            return (stripped, line, column)
        }

        // MARK: - LocalProcessDelegate

        nonisolated func processTerminated(_ source: SwiftTerm.LocalProcess, exitCode: Int32?) {
            Task { @MainActor in
                guard source === process else {
                    DiagnosticLogger.shared.log(
                        .info,
                        "processTerminated ignored (foreign source)",
                        context: "\(parent.session.label)(\(parent.session.id.uuidString.prefix(4))) gen=\(shortGeneration)",
                        source: "TerminalTabView"
                    )
                    return
                }

                let currentOwner = isCurrentOwner()
                if !currentOwner {
                    if Self.shouldRecoverOwnerBinding(
                        isCurrentOwner: currentOwner,
                        bridgeMatchesCoordinator: parent.session._processBridge === self
                    ) {
                        ensureOwnerBinding(reason: "processTerminated.recover")
                    } else {
                        DiagnosticLogger.shared.log(
                            .info,
                            "processTerminated ignored (stale)",
                            context: "\(parent.session.label)(\(parent.session.id.uuidString.prefix(4))) gen=\(shortGeneration)",
                            source: "TerminalTabView"
                        )
                        return
                    }
                }

                guard isCurrentOwner() else {
                    DiagnosticLogger.shared.log(
                        .info,
                        "processTerminated ignored (stale)",
                        context: "\(parent.session.label)(\(parent.session.id.uuidString.prefix(4))) gen=\(shortGeneration)",
                        source: "TerminalTabView"
                    )
                    return
                }
                DiagnosticLogger.shared.log(.info, "processTerminated", context: "\(parent.session.label)(\(parent.session.id.uuidString.prefix(4))) exitCode=\(exitCode ?? -1)", source: "TerminalTabView")
                flushPendingTerminalOutput(force: true)
                processIsDead = true
                parent.session.isAlive = false
            }
        }

        nonisolated func dataReceived(slice: ArraySlice<UInt8>) {
            Task { @MainActor in
                // Session was explicitly killed -- drop all further data
                guard parent.session._shouldPreserve else { return }
                let currentOwner = isCurrentOwner()
                if !currentOwner {
                    if Self.shouldRecoverOwnerBinding(
                        isCurrentOwner: currentOwner,
                        bridgeMatchesCoordinator: parent.session._processBridge === self
                    ) {
                        ensureOwnerBinding(reason: "dataReceived.recover")
                    } else {
                        DiagnosticLogger.shared.log(
                            .info,
                            "dataReceived ignored (stale)",
                            context: "\(parent.session.label)(\(parent.session.id.uuidString.prefix(4))) gen=\(shortGeneration)",
                            source: "TerminalTabView"
                        )
                        return
                    }
                }

                if terminalView == nil, let rebound = parent.session._cachedView as? SwiftTerm.TerminalView {
                    terminalView = rebound
                    DiagnosticLogger.shared.log(
                        .info,
                        "dataReceived rebound terminalView",
                        context: "\(parent.session.label)(\(parent.session.id.uuidString.prefix(4))) gen=\(shortGeneration)",
                        source: "TerminalTabView"
                    )
                }
                queueTerminalOutput(slice)
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
