import Foundation

extension TerminalTabView.Coordinator {

    // MARK: - Standalone scripts (~/.zion/bin/)

    static let zionBinDir: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.zion/bin"
    }()

    /// Install standalone scripts to ~/.zion/bin/ so they're available via PATH
    /// with zero terminal injection. Scripts are overwritten each time to stay current.
    static func installScripts(
        aiImageDisplay: Bool,
        homeDirectoryPath: String = FileManager.default.homeDirectoryForCurrentUser.path,
        zionBinDirOverride: String? = nil
    ) {
        let fm = FileManager.default
        let installBinDir = zionBinDirOverride ?? zionBinDir
        try? fm.createDirectory(atPath: installBinDir, withIntermediateDirectories: true)

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
            # Reserve a fixed margin above and below the image so the
            # prompt and surrounding transcript do not crowd the render.
            _zd_send() {
                printf '\\r\\n\\r\\n'
                printf '\\e]1337;File=inline=1;size=%d;name=%s;width=%dpx;preserveAspectRatio=1:' "$_zd_bytes" "$_zd_name" "$_zd_render_w"
                printf '%s' "$data"
                printf '\\a'
                printf '\\r\\n\\r\\n\\r\\n\\r\\n'
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
            let path = "\(installBinDir)/zion_display"
            try? script.write(toFile: path, atomically: true, encoding: .utf8)
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)

            // Shared prompt content for all AI CLI tools
            let zionImgPrompt = """
            You are a senior visual designer and SVG artist. Generate an image file for preview in Zion.

            **If input is a PATH** (contains `/` or ends in .png/.jpg/.jpeg/.gif/.svg):
            1. One-line description of the image.
            2. Tell the user to preview the file directly in Zion.

            **If input is a DESCRIPTION:**
            1. Generate a 600x400 SVG (horizontal). Think like a designer: plan the layout, choose a harmonious palette, and craft every detail with intention.

            **SVG compatibility (CRITICAL - rendering target is macOS QuickLook + sips fallback, NOT a browser):**
            Tested on macOS. QuickLook uses WebKit (broad support), but sips uses ImageIO/CoreGraphics (limited). SVGs MUST work in both.
            - `xmlns="http://www.w3.org/2000/svg"`, `viewBox="0 0 600 400"`
            - Verified safe elements: `<svg>`, `<rect>`, `<circle>`, `<ellipse>`, `<line>`, `<polyline>`, `<polygon>`, `<path>`, `<text>`, `<tspan>`, `<g>`, `<defs>`, `<linearGradient>`, `<radialGradient>`, `<stop>`, `<clipPath>`, `<pattern>`, `<symbol>`, `<use>` (inline `href` or `xlink:href` refs only)
            - Verified safe attributes: `fill`, `fill-rule`, `fill-opacity`, `stroke`, `stroke-width`, `stroke-dasharray`, `stroke-linecap`, `stroke-linejoin`, `stroke-opacity`, `opacity` (including on `<g>`), `transform` (translate/rotate/scale, chainable), `font-family`, `font-size`, `font-weight`, `text-anchor`, `dominant-baseline`, `text-decoration`, `letter-spacing`, `word-spacing`, `rx`, `ry`, `d`, `points`, `x`, `y`, `x1`, `y1`, `x2`, `y2`, `cx`, `cy`, `r`, `width`, `height`, `viewBox`, `id`, `href`, `xlink:href`, `patternUnits`, `patternContentUnits`, `gradientUnits`, `gradientTransform`
            - `<style>` blocks: Simple element and class selectors work (e.g., `.label { fill: red; }`). Prefer inline attributes for reliability, but `<style>` with basic selectors is acceptable for cleaner SVGs. NEVER use pseudo-selectors (`:first-child`, `:nth-child`, etc.) -- they silently fail in sips.
            - Forbidden (silently fail or break in sips): `<marker>` (arrowheads vanish -- draw arrow shapes manually as `<polygon>` or `<path>` instead), `<foreignObject>` (blank output), `<a>` (drops all children), `<filter>`, `<feGaussianBlur>`, `<feDropShadow>`, any `<fe*>` element, `<mask>`, `<image>`, `<switch>`, `<animate>`, `<animateTransform>`, `<animateMotion>`, `<set>`, CSS `@import`, CSS pseudo-selectors, CSS `@media` queries, CSS variables (`var()`), external URL refs, `data:` URIs, `@font-face`, JavaScript, event attributes
            - Fonts: `-apple-system`, `Helvetica Neue`, `Helvetica`, `Arial`, `monospace`, `sans-serif` only
            - Keep under 50KB

            **Design craft - treat every SVG like a portfolio piece:**
            - Color: Build a cohesive 3-5 color palette. Use subtle gradients for depth, not flat fills. Create visual hierarchy through color weight and saturation.
            - Typography: Size text for readability (min 11px for labels, 14px+ for headings). Use font-weight contrast to establish hierarchy. Ensure text never overlaps or clips.
            - Layout: Establish a clear visual grid. Balance negative space - don't cram elements or leave dead zones. Maintain consistent spacing and alignment throughout. Leave at least 20px margin from viewBox edges.
            - Depth: Layer elements with purpose. Use opacity and overlapping shapes to create dimensionality without filters. Lighter/darker fills simulate shadow and highlight.
            - Polish: Round line caps and joins (`stroke-linecap="round"`, `stroke-linejoin="round"`) for a refined look. Use consistent stroke widths. Every pixel should feel intentional.

            **Content-specific excellence:**
            - Flowcharts and diagrams: Draw arrowheads as small `<polygon>` or `<path>` triangles at connector endpoints (never use `<marker>`). Nodes aligned to a grid (multiples of 20px). Orthogonal routing for connectors, or smooth cubic beziers for organic flows. Minimum node size 100x50. Distinct colors per swimlane or category. Labels centered and legible inside nodes.
            - Charts and data: Clear labeled axes with tick marks. Evenly spaced data points. Subtle grid lines at low opacity. Distinct, accessible colors per data series. Data labels where they aid comprehension.
            - UI mockups and component previews: Rounded rectangles (`rx="8"`) for cards, buttons, and inputs. Realistic proportions - buttons look like buttons, inputs look like inputs. Use actual `<text>` for content, never placeholder lines. Match the visual tone of the context (light, dark, or branded).
            - Icons and illustrations: Center the artwork. Clean geometry with confident strokes. Prefer filled shapes with subtle detail over wireframe outlines. Every curve should feel deliberate.
            - Architecture and system diagrams: Group related components visually. Use color coding for different layers or services. Consistent box sizing for same-level components. Clear directional flow (top-to-bottom or left-to-right).

            2. Create `zion-image/` in the project root if needed, then save to `zion-image/<name>.svg`
            3. One-line description of what you drew.
            4. Stop after saving the file and tell the user it is ready for preview in Zion.
            5. On failure, simplify SVG and retry once. Common fixes: remove gradients, simplify text positioning, reduce path complexity.

            **Pre-save checklist (mental, do not output):**
            - Zero forbidden elements (no `<marker>`, `<filter>`, `<mask>`, `<a>`, `<foreignObject>`, `<image>`, `<animate>`)
            - All arrowheads are drawn as explicit `<polygon>`/`<path>` shapes
            - All `<use>` refs point to inline `<defs>` IDs only
            - If `<style>` is used, only element/class selectors (no pseudo-selectors, no `@media`, no `var()`)
            - All text uses system fonts listed above
            - Valid XML (closed tags, escaped `&` `<` `>` in text content)
            - Colors are harmonious, text is legible, layout is balanced

            **Rules:**
            - Describe BEFORE saving the file.
            - Keep descriptions to 1-2 lines max. Execute immediately.
            - The saved SVG will be displayed in Zion's built-in image preview automatically.
            - Never use Playwright, browser tools, screenshots, or external viewers for this workflow.
            - Never open the generated SVG/PNG in a browser tab.
            - After saving the file, stop. Do not do extra inspection unless generation fails.
            """

            // Install Claude Code slash command: /zion-img
            let home = homeDirectoryPath
            let commandsDir = "\(home)/.claude/commands"
            try? fm.createDirectory(atPath: commandsDir, withIntermediateDirectories: true)
            let claudeCommand = zionImgPrompt + "\n\nRequest: $ARGUMENTS"
            let commandPath = "\(commandsDir)/zion-img.md"
            try? claudeCommand.write(toFile: commandPath, atomically: true, encoding: .utf8)

            // Install Gemini CLI slash command: /zion-img
            let geminiCommandsDir = "\(home)/.gemini/commands"
            try? fm.createDirectory(atPath: geminiCommandsDir, withIntermediateDirectories: true)
            let tq = "\"\"\""  // TOML triple-quote delimiter
            let geminiPrompt = zionImgPrompt.replacingOccurrences(of: "`", with: "")
            let geminiCommand = "description = \"Generate an image file for preview in Zion\"\n\nprompt = \(tq)\n\(geminiPrompt)\n\nRequest: {{args}}\n\(tq)"
            let geminiCommandPath = "\(geminiCommandsDir)/zion-img.toml"
            try? geminiCommand.write(toFile: geminiCommandPath, atomically: true, encoding: .utf8)

            // Install Codex CLI skill: $zion-img
            let codexSkillDir = "\(home)/.agents/skills/zion-img"
            try? fm.createDirectory(atPath: codexSkillDir, withIntermediateDirectories: true)
            let codexSkill = """
            ---
            name: zion-img
            description: Use when the user asks to generate, draw, render, or prepare an image or SVG for preview in Zion. Also use when the user references zion-img or zion_display.
            ---

            \(zionImgPrompt)
            """
            let codexSkillPath = "\(codexSkillDir)/SKILL.md"
            try? codexSkill.write(toFile: codexSkillPath, atomically: true, encoding: .utf8)
        }
    }
}
