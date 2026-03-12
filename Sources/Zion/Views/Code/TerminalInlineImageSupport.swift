import Foundation

enum TerminalInlineImageSupport {
    static let defaultRenderWidth = 480
    static let defaultRenderHeight = 320
    private static let minimumColumnFitWidth = 240
    private static let minimumLineFitHeight = 160
    private static let pixelsPerColumn = 8
    private static let pixelsPerLine = 16

    static func zionDisplayScript() -> String {
        """
        #!/bin/zsh
        # zion_display — display images inline in Zion terminal (iTerm2 OSC 1337)
        # Installed by Zion Git Client

        _zd_save=0
        _zd_default_maxpx=\(defaultRenderWidth)
        _zd_default_maxhpx=\(defaultRenderHeight)
        _zd_maxpx="${ZION_IMAGE_MAX_WIDTH:-$_zd_default_maxpx}"
        _zd_maxhpx="${ZION_IMAGE_MAX_HEIGHT:-$_zd_default_maxhpx}"
        _zd_maxb64=2097152    # 2 MB base64 limit (prevents terminal flooding)

        _zd_require_int() {
            case "$1" in
                ''|*[!0-9]*) return 1 ;;
                *) return 0 ;;
            esac
        }

        while [ $# -gt 0 ]; do
            case "$1" in
                -h|--help)
                    cat <<'HELP'
        zion_display — display images inline in Zion terminal

        Usage: zion_display [--save] [--width pixels] <file>

        Options:
          --save            Save a copy to .zion/previews/ in the current git repo
          --width pixels    Override the max render width in pixels
          --help            Show this help

        Supported formats: PNG, JPEG, GIF, SVG
        SVG files are converted to PNG via bundled zion_svg2png (sandbox-safe).
        Large raster images are downscaled to fit the active pane automatically.
        Uses iTerm2 inline image protocol (OSC 1337).

        Environment:
          ZION_IMAGE_DISPLAY=1    Set when this feature is active
          ZION_TTY                Terminal device path (set by Zion)
          ZION_IMAGE_MAX_WIDTH    Default max render width override

        Examples:
          zion_display screenshot.png
          zion_display --width 360 diagram.svg
          zion_display --save diagram.svg
        HELP
                    exit 0
                    ;;
                --save)
                    _zd_save=1
                    shift
                    ;;
                --width)
                    shift
                    if [ $# -eq 0 ] || ! _zd_require_int "$1"; then
                        echo "zion_display: --width expects an integer pixel value" >&2
                        exit 1
                    fi
                    _zd_maxpx="$1"
                    shift
                    ;;
                --)
                    shift
                    break
                    ;;
                -*)
                    echo "zion_display: unknown option: $1" >&2
                    exit 1
                    ;;
                *)
                    break
                    ;;
            esac
        done

        if ! _zd_require_int "$_zd_maxpx"; then
            echo "zion_display: invalid render width: $_zd_maxpx" >&2
            exit 1
        fi
        if ! _zd_require_int "$_zd_maxhpx"; then
            echo "zion_display: invalid render height: $_zd_maxhpx" >&2
            exit 1
        fi

        if _zd_require_int "$COLUMNS"; then
            _zd_pane_maxpx=$(( COLUMNS * \(pixelsPerColumn) ))
            if [ "$_zd_pane_maxpx" -ge \(minimumColumnFitWidth) ] && [ "$_zd_pane_maxpx" -lt "$_zd_maxpx" ]; then
                _zd_maxpx="$_zd_pane_maxpx"
            fi
        fi
        if _zd_require_int "$LINES"; then
            _zd_pane_maxhpx=$(( (LINES - 4) * \(pixelsPerLine) ))
            if [ "$_zd_pane_maxhpx" -ge \(minimumLineFitHeight) ] && [ "$_zd_pane_maxhpx" -lt "$_zd_maxhpx" ]; then
                _zd_maxhpx="$_zd_pane_maxhpx"
            fi
        fi

        f="$1"
        [ -z "$f" ] && { echo "Usage: zion_display [--save] [--width pixels] <file> (--help for details)" >&2; exit 1; }
        [ ! -f "$f" ] && { echo "zion_display: file not found: $f" >&2; exit 1; }

        _zd_orig="$f"
        mime=$(file -b --mime-type "$f")
        _zd_cleanup=0

        case "$mime" in
            image/png|image/jpeg|image/gif)
                # Downscale large raster images to keep payload manageable.
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
                # Try zion_svg2png first (bundled, sandbox-safe, uses CoreSVG).
                if command -v zion_svg2png >/dev/null 2>&1; then
                    zion_svg2png "$f" "$_zd_maxpx" --out "$tmp" 2>/dev/null
                fi
                # Fallback 1: qlmanage (best quality but needs WindowServer).
                if [ ! -s "$tmp" ]; then
                    qlmanage -t -s "$_zd_maxpx" -o "${TMPDIR:-/tmp}" "$f" >/dev/null 2>&1 \\
                        && mv "${TMPDIR:-/tmp}/$(basename "$f").png" "$tmp" 2>/dev/null
                fi
                # Fallback 2: sips (uses ImageIO, handles simpler SVGs).
                if [ ! -s "$tmp" ]; then
                    sips -s format png -Z "$_zd_maxpx" "$f" --out "$tmp" >/dev/null 2>&1
                fi
                # Fallback 3: rsvg-convert (if installed via Homebrew).
                if [ ! -s "$tmp" ] && command -v rsvg-convert >/dev/null 2>&1; then
                    rsvg-convert -w "$_zd_maxpx" -o "$tmp" "$f" 2>/dev/null
                fi
                if [ ! -s "$tmp" ]; then
                    rm -f "$tmp"
                    echo "zion_display: SVG conversion failed. All converters failed." >&2
                    echo "  Hint: brew install librsvg (adds rsvg-convert)" >&2
                    exit 1
                fi
                f="$tmp"; _zd_cleanup=1
                ;;
            *) echo "zion_display: unsupported type: $mime" >&2; exit 1 ;;
        esac

        # Base64 encode and check size guard.
        data=$(base64 -b 0 < "$f")
        if [ "${#data}" -gt "$_zd_maxb64" ]; then
            echo "zion_display: image too large ($(( ${#data} / 1024 ))KB encoded). Max $(( _zd_maxb64 / 1024 ))KB." >&2
            [ "$_zd_cleanup" = 1 ] && rm -f "$f"
            exit 1
        fi

        # Actual file size in bytes (for OSC 1337 size= parameter).
        _zd_bytes=$(wc -c < "$f" | tr -d ' ')
        _zd_name=$(printf '%s' "$(basename "$_zd_orig")" | base64)

        # Determine actual pixel width for OSC width parameter.
        _zd_render_w="$_zd_maxpx"
        _zd_render_h="$_zd_maxhpx"
        _zd_actual_w=$(sips -g pixelWidth "$f" 2>/dev/null | awk '/pixelWidth/{print $2}')
        _zd_actual_h=$(sips -g pixelHeight "$f" 2>/dev/null | awk '/pixelHeight/{print $2}')
        if [ -n "$_zd_actual_w" ] && [ "$_zd_actual_w" -lt "$_zd_maxpx" ] 2>/dev/null; then
            _zd_render_w="$_zd_actual_w"
        fi
        if [ -n "$_zd_actual_h" ] && [ "$_zd_actual_h" -lt "$_zd_maxhpx" ] 2>/dev/null; then
            _zd_render_h="$_zd_actual_h"
        fi

        if [ -n "$_zd_actual_w" ] && [ -n "$_zd_actual_h" ] && [ "$_zd_actual_w" -gt 0 ] 2>/dev/null && [ "$_zd_actual_h" -gt 0 ] 2>/dev/null; then
            _zd_fit_w=$(( (_zd_actual_w * _zd_maxhpx) / _zd_actual_h ))
            if [ "$_zd_fit_w" -gt 0 ] 2>/dev/null && [ "$_zd_fit_w" -lt "$_zd_render_w" ]; then
                _zd_render_w="$_zd_fit_w"
            fi
            _zd_render_h=$(( (_zd_actual_h * _zd_render_w) / _zd_actual_w ))
            if [ "$_zd_render_h" -lt 1 ] 2>/dev/null; then
                _zd_render_h=1
            fi
        fi

        # Resolve output target: ZION_TTY > /dev/tty > fail loudly.
        _zd_out=""
        if [ -n "$ZION_TTY" ] && [ -w "$ZION_TTY" ]; then
            _zd_out="$ZION_TTY"
        elif printf '' > /dev/tty 2>/dev/null; then
            _zd_out="/dev/tty"
        fi

        if [ -z "$_zd_out" ]; then
            echo "zion_display: no terminal TTY available for inline rendering." >&2
            echo "  Run zion_display as a standalone terminal command so it can write to the pane." >&2
            [ "$_zd_cleanup" = 1 ] && rm -f "$f"
            exit 1
        fi

        # Send via iTerm2 OSC 1337.
        # CR+LF after the image resets the terminal cursor to column 0.
        _zd_send() {
            printf '\\e]1337;File=inline=1;size=%d;name=%s;width=%dpx;height=%dpx;preserveAspectRatio=1:' "$_zd_bytes" "$_zd_name" "$_zd_render_w" "$_zd_render_h"
            printf '%s' "$data"
            printf '\\a'
            printf '\\r\\n'
        }
        _zd_send > "$_zd_out"

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
    }

    static func zionImgPrompt() -> String {
        """
        Display an image or draw an SVG and show it inline.

        **If input is a PATH** (contains `/` or ends in .png/.jpg/.jpeg/.gif/.svg):
        1. One-line description of the image.
        2. Run `~/.zion/bin/zion_display <path>` as a standalone terminal command.

        **If input is a DESCRIPTION:**
        1. Generate a 600x400 SVG (horizontal). Rules:
           - `xmlns="http://www.w3.org/2000/svg"`, `viewBox="0 0 600 400"`
           - Allowed: `<rect>`, `<circle>`, `<ellipse>`, `<line>`, `<polyline>`, `<polygon>`, `<path>`, `<text>`, `<g>`, `<defs>`, `<linearGradient>`, `<radialGradient>`, `<clipPath>`
           - Forbidden: `<foreignObject>`, `<filter>`, `<feGaussianBlur>`, `<mask>`, CSS `@import`, external refs
           - Keep under 50KB
        2. Save to `~/Library/Caches/Zion/images/<name>.svg`
        3. One-line description of what you drew.
        4. Run `~/.zion/bin/zion_display ~/Library/Caches/Zion/images/<name>.svg` as a standalone terminal command.
        5. `zion_display` auto-fits the image to the active pane. If you need a smaller render, pass `--width <pixels>`.
        6. On failure, simplify SVG (remove gradients/text/complex paths) and retry once.
        7. On second failure, generate a PNG directly using Python if available:
           `python3 -c "from PIL import Image, ImageDraw; ..."`
           If no Python/PIL, report the error with the hint: `brew install librsvg`

        With `--save`: use `~/.zion/bin/zion_display --save <file>` instead.

        **Rules:**
        - Describe BEFORE displaying.
        - Never combine create-and-display into one compound shell command.
        - Do not pipe, chain, or background the `zion_display` step.
        - Prefer a TTY-backed command execution for `zion_display`.
        - If `zion_display` reports that no terminal TTY is available, stop and report that instead of retrying in the same captured command mode.
        - After displaying, do not add follow-up narration unless the user asked for it.
        """
    }
}
