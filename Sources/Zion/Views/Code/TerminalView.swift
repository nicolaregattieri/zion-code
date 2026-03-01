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
            if let zionView = cachedView as? ZionTerminalView {
                zionView.onFileDrop = { [coordinator = context.coordinator] text in
                    coordinator.sendText(text)
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
        terminalView.onFileDrop = { [coordinator = context.coordinator] text in
            coordinator.sendText(text)
        }
        terminalView.allowMouseReporting = true
        terminalView.terminalDelegate = context.coordinator

        // Apply custom terminal options BEFORE theme — applyCustomOptions replaces the
        // Terminal instance with default colors, so theme must come after.
        let scrollback = UserDefaults.standard.integer(forKey: "terminal.scrollbackSize")
        let imageRendering = UserDefaults.standard.bool(forKey: "terminal.imageRendering")
        var opts = SwiftTerm.TerminalOptions()
        opts.scrollback = scrollback == Int.max ? Int.max : max(100, scrollback)
        opts.enableSixelReported = imageRendering
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
        log.log(.info, "dismantleNSView", context: "\(s.label)(\(s.id.uuidString.prefix(4))) preserve=\(s._shouldPreserve) alive=\(s.isAlive) pid=\(s._shellPid)", source: "TerminalTabView")
        // If session was explicitly killed, let everything deallocate naturally.
        guard s._shouldPreserve else { return }
        // Cache coordinator + NSView on session so they survive view tree restructuring.
        // Explicit kills happen via session.killCachedProcess() in the ViewModel.
        // Note: don't unregister send callback here — reattach() re-registers it,
        // and SwiftUI may create the new view BEFORE calling dismantle on the old one.
        s._cachedView = nsView
        s._processBridge = coordinator
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
        var lastAppliedTransparent: Bool = false
        private var pendingResizeTask: Task<Void, Never>?
        private var shiftEnterMonitor: Any?
        private var mouseUpMonitor: Any?

        init(_ parent: TerminalTabView) {
            self.parent = parent
        }

        // MARK: - Process lifecycle

        func startProcess(view: SwiftTerm.TerminalView) {
            self.terminalView = view
            installShiftEnterMonitor()
            installMouseUpMonitor()
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
                env["COLORTERM"] = "truecolor"
                env["TERM_PROGRAM"] = "Zion"
                env["TERM_PROGRAM_VERSION"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                env["LANG"] = "en_US.UTF-8"
                env["PATH"] = "\(Self.zionBinDir):/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:" + (env["PATH"] ?? "")

                let aiImageDisplay = UserDefaults.standard.bool(forKey: "terminal.aiImageDisplay")
                if aiImageDisplay {
                    env["ZION_IMAGE_DISPLAY"] = "1"
                }

                let ntfyTopic = UserDefaults.standard.string(forKey: "zion.ntfy.topic") ?? ""
                let ntfyServer = UserDefaults.standard.string(forKey: "zion.ntfy.serverURL") ?? "https://ntfy.sh"
                if !ntfyTopic.isEmpty {
                    env["ZION_NTFY_TOPIC"] = ntfyTopic
                    env["ZION_NTFY_SERVER"] = ntfyServer
                }

                // Install standalone scripts to ~/.zion/bin/
                let hasFeatures = aiImageDisplay || !ntfyTopic.isEmpty
                if hasFeatures {
                    Self.installScripts(
                        aiImageDisplay: aiImageDisplay,
                        ntfyTopic: ntfyTopic,
                        ntfyServer: ntfyServer
                    )

                    // Only auto-append AI config blocks to project files if user opted in
                    let autoAppend = UserDefaults.standard.bool(forKey: "terminal.autoAppendAIConfig")
                    if autoAppend {
                        Self.appendZionBlock(
                            projectRoot: url,
                            aiImageDisplay: aiImageDisplay,
                            ntfyTopic: ntfyTopic,
                            ntfyServer: ntfyServer
                        )
                    }
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
            installShiftEnterMonitor()
            installMouseUpMonitor()

            // Re-wire file drop handler for Finder drag-and-drop
            if let zionView = view as? ZionTerminalView {
                zionView.onFileDrop = { [weak self] text in
                    self?.sendText(text)
                }
            }

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
            removeMouseUpMonitor()
            parent.session._shellPid = 0
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

        private func installShiftEnterMonitor() {
            guard shiftEnterMonitor == nil else { return }
            shiftEnterMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                guard self.isShiftReturn(event), self.isTerminalFocused else { return event }
                self.insertSoftLineBreak()
                return nil
            }
        }

        private func removeShiftEnterMonitor() {
            if let monitor = shiftEnterMonitor {
                NSEvent.removeMonitor(monitor)
                shiftEnterMonitor = nil
            }
        }

        private func installMouseUpMonitor() {
            guard mouseUpMonitor == nil else { return }
            mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                guard let self, self.isTerminalFocused else { return event }
                guard UserDefaults.standard.bool(forKey: "terminal.copyOnSelect") else { return event }
                guard let view = self.terminalView, view.selectedRange().length > 0 else { return event }
                view.copy(self)
                return event
            }
        }

        private func removeMouseUpMonitor() {
            if let monitor = mouseUpMonitor {
                NSEvent.removeMonitor(monitor)
                mouseUpMonitor = nil
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

        // MARK: - Standalone scripts (~/.zion/bin/)

        private static let zionBinDir: String = {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return "\(home)/.zion/bin"
        }()

        /// Install standalone scripts to ~/.zion/bin/ so they're available via PATH
        /// with zero terminal injection. Scripts are overwritten each time to stay current.
        private static func installScripts(
            aiImageDisplay: Bool,
            ntfyTopic: String,
            ntfyServer: String
        ) {
            let fm = FileManager.default
            try? fm.createDirectory(atPath: zionBinDir, withIntermediateDirectories: true)

            if aiImageDisplay {
                let script = """
                #!/bin/zsh
                # zion_display — display images inline in Zion terminal (iTerm2 OSC 1337)
                # Installed by Zion Git Client

                _zd_save=0
                _zd_maxpx=600         # max render width (keeps base64 payload small)
                _zd_maxb64=2097152    # 2 MB base64 limit (prevents terminal flooding)

                case "$1" in
                    -h|--help)
                        cat <<'HELP'
                zion_display — display images inline in Zion terminal

                Usage: zion_display [--save] <file>

                Options:
                  --save    Save a copy to .zion/previews/ in the current git repo
                  --help    Show this help

                Supported formats: PNG, JPEG, GIF, SVG
                SVG files are converted to PNG via macOS qlmanage (no dependencies).
                Large raster images are downscaled to 600px width automatically.
                Uses iTerm2 inline image protocol (OSC 1337).

                Environment:
                  ZION_IMAGE_DISPLAY=1  Set when this feature is active
                  ZION_TTY              Terminal device path (set by Zion)

                Examples:
                  zion_display screenshot.png
                  zion_display --save diagram.svg
                HELP
                        exit 0
                        ;;
                    --save) _zd_save=1; shift ;;
                esac

                f="$1"
                [ -z "$f" ] && { echo "Usage: zion_display [--save] <file> (--help for details)" >&2; exit 1; }
                [ ! -f "$f" ] && { echo "zion_display: file not found: $f" >&2; exit 1; }

                _zd_orig="$f"
                mime=$(file -b --mime-type "$f")
                _zd_cleanup=0

                case "$mime" in
                    image/png|image/jpeg|image/gif)
                        # Downscale large raster images to keep payload manageable
                        _zd_w=$(sips -g pixelWidth "$f" 2>/dev/null | awk '/pixelWidth/{print $2}')
                        if [ -n "$_zd_w" ] && [ "$_zd_w" -gt "$_zd_maxpx" ] 2>/dev/null; then
                            tmp=$(mktemp "${TMPDIR:-/tmp}/zion_img_XXXXXX.png")
                            sips --resampleWidth "$_zd_maxpx" "$f" --out "$tmp" >/dev/null 2>&1
                            if [ -f "$tmp" ] && [ -s "$tmp" ]; then
                                f="$tmp"; _zd_cleanup=1
                            else
                                rm -f "$tmp"
                            fi
                        fi
                        ;;
                    image/svg+xml)
                        tmp=$(mktemp "${TMPDIR:-/tmp}/zion_img_XXXXXX.png")
                        # Try qlmanage first (best quality for SVGs)
                        qlmanage -t -s "$_zd_maxpx" -o "${TMPDIR:-/tmp}" "$f" >/dev/null 2>&1 \\
                            && mv "${TMPDIR:-/tmp}/$(basename "$f").png" "$tmp" 2>/dev/null
                        # Fallback 1: sips (uses ImageIO, handles simpler SVGs)
                        if [ ! -s "$tmp" ]; then
                            sips -s format png -Z "$_zd_maxpx" "$f" --out "$tmp" >/dev/null 2>&1
                        fi
                        # Fallback 2: rsvg-convert (if installed via Homebrew)
                        if [ ! -s "$tmp" ] && command -v rsvg-convert >/dev/null 2>&1; then
                            rsvg-convert -w "$_zd_maxpx" -o "$tmp" "$f" 2>/dev/null
                        fi
                        if [ ! -s "$tmp" ]; then
                            rm -f "$tmp"
                            echo "zion_display: SVG conversion failed (tried qlmanage, sips, rsvg-convert)" >&2
                            exit 1
                        fi
                        f="$tmp"; _zd_cleanup=1
                        ;;
                    *) echo "zion_display: unsupported type: $mime" >&2; exit 1 ;;
                esac

                # Base64 encode and check size guard
                data=$(base64 -b 0 < "$f")
                if [ "${#data}" -gt "$_zd_maxb64" ]; then
                    echo "zion_display: image too large ($(( ${#data} / 1024 ))KB encoded). Max $(( _zd_maxb64 / 1024 ))KB." >&2
                    [ "$_zd_cleanup" = 1 ] && rm -f "$f"
                    exit 1
                fi

                # Actual file size in bytes (for OSC 1337 size= parameter)
                _zd_bytes=$(wc -c < "$f" | tr -d ' ')
                _zd_name=$(printf '%s' "$(basename "$_zd_orig")" | base64)

                # Determine actual pixel width for OSC width parameter
                _zd_render_w="$_zd_maxpx"
                _zd_actual_w=$(sips -g pixelWidth "$f" 2>/dev/null | awk '/pixelWidth/{print $2}')
                if [ -n "$_zd_actual_w" ] && [ "$_zd_actual_w" -lt "$_zd_maxpx" ] 2>/dev/null; then
                    _zd_render_w="$_zd_actual_w"
                fi

                # Resolve output target: ZION_TTY > /dev/tty > stdout
                _zd_out=""
                if [ -n "$ZION_TTY" ] && [ -w "$ZION_TTY" ]; then
                    _zd_out="$ZION_TTY"
                elif printf '' > /dev/tty 2>/dev/null; then
                    _zd_out="/dev/tty"
                fi

                # Send via iTerm2 OSC 1337.
                # CR+LF after the image resets the terminal cursor to column 0.
                _zd_send() {
                    printf '\\e]1337;File=inline=1;size=%d;name=%s;width=%dpx;preserveAspectRatio=1:' "$_zd_bytes" "$_zd_name" "$_zd_render_w"
                    printf '%s' "$data"
                    printf '\\a'
                    printf '\\r\\n'
                }
                if [ -n "$_zd_out" ]; then
                    _zd_send > "$_zd_out"
                else
                    _zd_send
                fi

                if [ "$_zd_save" = 1 ]; then
                    root=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
                    dir="$root/.zion/previews"
                    mkdir -p "$dir"
                    ts=$(date +%Y-%m-%d_%H%M%S)
                    base=$(basename "$_zd_orig")
                    cp "$_zd_orig" "$dir/${ts}_${base}"
                    echo "Saved: $dir/${ts}_${base}"
                fi

                [ "$_zd_cleanup" = 1 ] && rm -f "$f"
                """
                let path = "\(zionBinDir)/zion_display"
                try? script.write(toFile: path, atomically: true, encoding: .utf8)
                try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)

                // Install Claude Code slash command: /zion-img
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let commandsDir = "\(home)/.claude/commands"
                try? fm.createDirectory(atPath: commandsDir, withIntermediateDirectories: true)
                let commandContent = """
                Display an image inline in this terminal.

                IMPORTANT: Always describe the image BEFORE running `zion_display`. The image renders directly on the terminal and any text printed after it will overlap. Write your description first, then display.

                First, determine if the request is a **file path** or a **description**:

                **If the input is a file path** (contains `/` or `.png`, `.jpg`, `.jpeg`, `.gif`, `.svg`):
                1. Briefly describe what the image shows.
                2. Run: `zion_display <filepath>`

                **If the input is a description**:
                1. Create an SVG that macOS can render. Follow these rules strictly:
                   - Use `xmlns="http://www.w3.org/2000/svg"` on the root `<svg>` element
                   - Use only basic SVG elements: `<rect>`, `<circle>`, `<ellipse>`, `<line>`, `<polyline>`, `<polygon>`, `<path>`, `<text>`, `<g>`, `<defs>`, `<linearGradient>`, `<radialGradient>`, `<clipPath>`
                   - Do NOT use `<foreignObject>`, `<filter>`, `<feGaussianBlur>`, `<mask>`, CSS `@import`, or external references
                   - Set a proper `viewBox` (e.g. `viewBox="0 0 600 400"`)
                   - Keep it under 50KB — prefer clean shapes over excessive detail
                2. Save using Bash `mkdir -p ~/Library/Caches/Zion/images && cat > ~/Library/Caches/Zion/images/<name>.svg << 'SVGEOF'` (NOT the Write tool). Always use `~/Library/Caches/Zion/images/`.
                3. Briefly describe what you drew.
                4. Run: `zion_display ~/Library/Caches/Zion/images/<name>.svg`
                5. If `zion_display` fails with "SVG conversion failed", simplify the SVG (remove gradients, complex paths, or text) and retry.

                If the request mentions "--save", use `zion_display --save <file>` instead.

                Request: $ARGUMENTS
                """
                let commandPath = "\(commandsDir)/zion-img.md"
                try? commandContent.write(toFile: commandPath, atomically: true, encoding: .utf8)
            }

            // zion_ai_setup — manual fallback for creating new AI config files
            let hasImage = aiImageDisplay
            let hasNtfy = !ntfyTopic.isEmpty

            var featuresList = ""
            if hasImage { featuresList += "\n  - Inline image display (zion_display)" }
            if hasNtfy { featuresList += "\n  - Push notifications (ntfy)" }

            // Build the block lines that zion_ai_setup will embed
            var blockLines = ""
            if hasImage {
                blockLines += """

                ## Inline Image Display
                Use `/zion-img <description>` to generate and display images inline.
                Or run directly: `zion_display <file>` (supports PNG, JPEG, GIF, SVG).

                """
            }
            if hasNtfy {
                blockLines += """

                ## Push Notifications
                When you complete a significant task, notify the user:
                curl -s -H "Title: Done" -H "Priority: 3" -H "Tags: white_check_mark" \\\\
                  -d "[Brief description]" "\(ntfyServer)/\(ntfyTopic)"
                Send for: plan completion, implementation done, test results, migrations, errors.
                Do NOT send for: file reads, intermediate steps, questions.

                """
            }

            let setupScript = """
            #!/bin/zsh
            # zion_ai_setup — configure AI tools to use Zion terminal features
            # Installed by Zion Git Client

            _zas_block='\(blockLines)'

            case "$1" in
                -h|--help|"")
                    cat <<'HELP'
            zion_ai_setup — configure AI tools to use Zion terminal features

            Usage: zion_ai_setup <tool>

            Supported tools:
              claude      CLAUDE.md
              codex       AGENTS.md
              cursor      .cursorrules
              copilot     .github/copilot-instructions.md
              windsurf    .windsurfrules
              cody        .cody/instructions.md
              gemini      GEMINI.md

            Features configured:\(featuresList)

            Creates the file if needed and appends a Zion instruction block.
            Use this when your project does not yet have the config file.
            Existing files with a Zion block are updated automatically on terminal start.

            Example: zion_ai_setup claude
            HELP
                    exit 0
                    ;;
                claude)   _zas_f="CLAUDE.md" ;;
                codex)    _zas_f="AGENTS.md" ;;
                cursor)   _zas_f=".cursorrules" ;;
                copilot)  _zas_f=".github/copilot-instructions.md" ;;
                windsurf) _zas_f=".windsurfrules" ;;
                cody)     _zas_f=".cody/instructions.md" ;;
                gemini)   _zas_f="GEMINI.md" ;;
                *)
                    echo "zion_ai_setup: unknown tool '$1'. Run zion_ai_setup --help" >&2
                    exit 1
                    ;;
            esac

            _zas_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
                echo "zion_ai_setup: not inside a git repository" >&2
                exit 1
            }

            _zas_path="$_zas_root/$_zas_f"

            if [ -f "$_zas_path" ] && grep -q 'Zion Terminal' "$_zas_path" 2>/dev/null; then
                echo "Already configured: $_zas_path contains Zion Terminal block"
                exit 0
            fi

            _zas_full="<!-- ZION:START (managed by Zion Git Client \\u2014 do not edit) -->
            # Zion Terminal
            $_zas_block
            <!-- ZION:END -->"

            echo ""
            echo "Will \(hasImage || hasNtfy ? "append to" : "create"): $_zas_path"
            echo "---"
            echo "$_zas_full"
            echo "---"
            echo ""
            printf "Proceed? [y/N] "
            read -r _zas_ans
            case "$_zas_ans" in
                [Yy]*)
                    mkdir -p "$(dirname "$_zas_path")" 2>/dev/null
                    printf '\\n%s\\n' "$_zas_full" >> "$_zas_path"
                    echo "Done: $_zas_path updated"
                    ;;
                *) echo "Cancelled" ;;
            esac
            """
            let setupPath = "\(zionBinDir)/zion_ai_setup"
            try? setupScript.write(toFile: setupPath, atomically: true, encoding: .utf8)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: setupPath)
        }

        // MARK: - Auto-append Zion block to AI config files

        private static let startMarker = "<!-- ZION:START (managed by Zion Git Client \u{2014} do not edit) -->"
        private static let endMarker = "<!-- ZION:END -->"

        private static let knownConfigFiles = [
            "CLAUDE.md",
            ".cursorrules",
            ".github/copilot-instructions.md",
            ".windsurfrules",
            ".cody/instructions.md",
            "AGENTS.md",
            "GEMINI.md",
        ]

        /// Scan project root for known AI config files and append/update the Zion instruction block.
        static func appendZionBlock(projectRoot: URL, aiImageDisplay: Bool, ntfyTopic: String, ntfyServer: String) {
            let fm = FileManager.default

            for configFile in knownConfigFiles {
                let fileURL = projectRoot.appendingPathComponent(configFile)
                guard fm.fileExists(atPath: fileURL.path) else { continue }

                // Don't write through symlinks
                if let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
                   attrs[.type] as? FileAttributeType == .typeSymbolicLink {
                    continue
                }

                guard var content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

                let block = buildMarkdownBlock(aiImageDisplay: aiImageDisplay, ntfyTopic: ntfyTopic, ntfyServer: ntfyServer)

                // Check if block already exists
                if let startRange = content.range(of: startMarker),
                   let endRange = content.range(of: endMarker) {
                    // Replace existing block
                    content.replaceSubrange(startRange.lowerBound..<endRange.upperBound, with: block)
                    try? content.write(to: fileURL, atomically: true, encoding: .utf8)
                } else if !content.contains("Zion Terminal") {
                    // Append new block
                    if !content.hasSuffix("\n") { content += "\n" }
                    content += "\n" + block + "\n"
                    try? content.write(to: fileURL, atomically: true, encoding: .utf8)
                }
            }
        }

        /// Build the markdown instruction block with only enabled features.
        private static func buildMarkdownBlock(aiImageDisplay: Bool, ntfyTopic: String, ntfyServer: String) -> String {
            var sections: [String] = []

            if aiImageDisplay {
                sections.append("""
                ## Inline Image Display
                Use `/zion-img <description>` to generate and display images inline.
                Or run directly: `zion_display <file>` (supports PNG, JPEG, GIF, SVG).
                """)
            }

            if !ntfyTopic.isEmpty {
                sections.append("""
                ## Push Notifications
                When you complete a significant task, notify the user:
                curl -s -H "Title: Done" -H "Priority: 3" -H "Tags: white_check_mark" \\
                  -d "[Brief description]" "\(ntfyServer)/\(ntfyTopic)"
                Send for: plan completion, implementation done, test results, migrations, errors.
                Do NOT send for: file reads, intermediate steps, questions.
                """)
            }

            return """
            \(startMarker)
            # Zion Terminal

            \(sections.joined(separator: "\n\n"))
            \(endMarker)
            """
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

        nonisolated func bell(source: SwiftTerm.TerminalView) {
            let mode = UserDefaults.standard.string(forKey: "terminal.bellMode") ?? "system"
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
            guard UserDefaults.standard.bool(forKey: "terminal.openHyperlinks") else { return }
            if let fixedup = link.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                if let url = NSURLComponents(string: fixedup) {
                    if let actualUrl = url.url {
                        NSWorkspace.shared.open(actualUrl)
                    }
                }
            }
        }

        // MARK: - LocalProcessDelegate

        nonisolated func processTerminated(_ source: SwiftTerm.LocalProcess, exitCode: Int32?) {
            Task { @MainActor in
                DiagnosticLogger.shared.log(.info, "processTerminated", context: "\(parent.session.label)(\(parent.session.id.uuidString.prefix(4))) exitCode=\(exitCode ?? -1)", source: "TerminalTabView")
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
