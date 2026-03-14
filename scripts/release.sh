#!/usr/bin/env bash
set -euo pipefail

# Zion Release Script
# Builds app, notarizes app + DMG when configured, Sparkle-signs the final DMG,
# generates appcast, and uploads release assets.
#
# Usage:
#   ./scripts/release.sh          — build + notarize (if configured) + generate appcast
#   ./scripts/release.sh upload   — also upload to GitHub Releases (requires gh CLI)
#
# Prerequisites:
#   - Sparkle tools at /tmp/bin/ (sign_update). Install once with:
#       cd /tmp
#       curl -LO https://github.com/sparkle-project/Sparkle/releases/download/2.8.1/Sparkle-2.8.1.tar.xz
#       tar xf Sparkle-2.8.1.tar.xz
#   - EdDSA key pair in macOS Keychain (created automatically by sign_update on first run)
#   - Optional `.zion-release.local` file with:
#       export CODESIGN_IDENTITY="Developer ID Application: Your Name"
#       export NOTARY_KEYCHAIN_PROFILE="your-notary-profile"
#   - gh CLI authenticated as repo owner (for upload)

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

DEFAULT_ENV_FILE="$ROOT_DIR/.zion-release.local"
LEGACY_ENV_FILE="$ROOT_DIR/.env.notarize"
ENV_FILE="${ZION_ENV_FILE:-$DEFAULT_ENV_FILE}"
if [ ! -f "$ENV_FILE" ] && [ "$ENV_FILE" = "$DEFAULT_ENV_FILE" ] && [ -f "$LEGACY_ENV_FILE" ]; then
    ENV_FILE="$LEGACY_ENV_FILE"
fi
if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
fi

export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/clang-module-cache"

DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DIST_DIR/Zion.app"
ZIP_PATH="$DIST_DIR/Zion.zip"
DMG_PATH="$DIST_DIR/Zion.dmg"
APPCAST_PATH="$DIST_DIR/appcast.xml"
SPARKLE_BIN="/tmp/bin"
GITHUB_REPO="nicolaregattieri/zion-code"
DOWNLOAD_BASE="https://github.com/$GITHUB_REPO/releases/download"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"
ENABLE_APPLE_NOTARIZATION=0

if [ "$CODESIGN_IDENTITY" != "-" ] && [ -n "$NOTARY_KEYCHAIN_PROFILE" ]; then
    ENABLE_APPLE_NOTARIZATION=1
fi

if [ "$CODESIGN_IDENTITY" != "-" ] && [ -z "$NOTARY_KEYCHAIN_PROFILE" ]; then
    echo "WARNING: CODESIGN_IDENTITY is set but NOTARY_KEYCHAIN_PROFILE is empty."
    echo "         Apple notarization will be skipped."
fi

if [ "${1:-}" = "upload" ] && [ "$ENABLE_APPLE_NOTARIZATION" -ne 1 ]; then
    echo "ERROR: Refusing to upload a release without Apple notarization enabled."
    echo "       Set CODESIGN_IDENTITY and NOTARY_KEYCHAIN_PROFILE via .zion-release.local or ZION_ENV_FILE."
    exit 1
fi

# --- Check Sparkle sign_update exists ---
if [ ! -f "$SPARKLE_BIN/sign_update" ]; then
    echo "ERROR: Sparkle sign_update not found at $SPARKLE_BIN/sign_update"
    echo ""
    echo "Install once with:"
    echo "  cd /tmp"
    echo "  curl -LO https://github.com/sparkle-project/Sparkle/releases/download/2.8.1/Sparkle-2.8.1.tar.xz"
    echo "  tar xf Sparkle-2.8.1.tar.xz"
    exit 1
fi

# --- Pre-flight checks ---
echo ""
echo "=== Pre-flight: Running tests ==="
if ! swift test --quiet 2>&1; then
    echo "WARNING: Tests failed. Continue anyway? (y/N)"
    read -r ans
    case "$ans" in
        [Yy]*) echo "Continuing despite test failures..." ;;
        *) echo "Aborted."; exit 1 ;;
    esac
fi

# --- Step 1: Build app ---
echo ""
echo "=== Step 1/6: Building Zion.app ==="
./scripts/make-app.sh

# --- Read version from Info.plist ---
VERSION=$(defaults read "$APP_PATH/Contents/Info" CFBundleShortVersionString)
BUILD=$(defaults read "$APP_PATH/Contents/Info" CFBundleVersion)
TAG="v$VERSION"

echo "  Version: $VERSION (build $BUILD)"

if [ "$ENABLE_APPLE_NOTARIZATION" -eq 1 ]; then
    echo "  Apple signing identity: $CODESIGN_IDENTITY"
    echo "  Notary profile:         $NOTARY_KEYCHAIN_PROFILE"

    echo ""
    echo "=== Step 2/6: Notarizing Zion.app ==="
    rm -f "$ZIP_PATH"
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
    xcrun stapler staple "$APP_PATH"
    spctl -a -t exec -vv "$APP_PATH"
else
    echo "  Apple notarization disabled (set CODESIGN_IDENTITY and NOTARY_KEYCHAIN_PROFILE to enable)"
fi

# --- Step 3: Create DMG ---
echo ""
echo "=== Step 3/6: Creating DMG ==="
./scripts/make-dmg.sh

if [ "$ENABLE_APPLE_NOTARIZATION" -eq 1 ]; then
    echo ""
    echo "=== Step 4/6: Signing and notarizing Zion.dmg ==="
    codesign --force --sign "$CODESIGN_IDENTITY" --timestamp "$DMG_PATH"
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
fi

# --- Step 5: Sign DMG with EdDSA ---
echo ""
echo "=== Step 5/6: Signing DMG for Sparkle ==="
SIGN_OUTPUT=$("$SPARKLE_BIN/sign_update" "$DMG_PATH")
echo "$SIGN_OUTPUT"

# Parse signature and length from sign_update output
ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
DMG_LENGTH=$(echo "$SIGN_OUTPUT" | grep -o 'length="[^"]*"' | cut -d'"' -f2)

if [ -z "$ED_SIGNATURE" ] || [ -z "$DMG_LENGTH" ]; then
    echo "ERROR: Failed to parse signature from sign_update output"
    exit 1
fi

# --- Step 6: Generate appcast.xml ---
echo ""
echo "=== Step 6/6: Generating appcast.xml ==="
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S %z")

cat > "$APPCAST_PATH" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Zion Updates</title>
    <language>en</language>
    <item>
      <title>Zion $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure
        url="$DOWNLOAD_BASE/$TAG/Zion.dmg"
        type="application/octet-stream"
        length="$DMG_LENGTH"
        sparkle:edSignature="$ED_SIGNATURE"
      />
    </item>
  </channel>
</rss>
EOF

echo "Appcast generated at: $APPCAST_PATH"

# --- Summary ---
echo ""
echo "=== Release ready ==="
echo "  Version:   $VERSION (build $BUILD)"
echo "  Tag:       $TAG"
echo "  DMG:       $DMG_PATH"
echo "  Appcast:   $APPCAST_PATH"
echo "  Signature: $ED_SIGNATURE"

echo ""
echo "  Reminder: run /documenter to sync docs with recent changes."

# --- Upload to GitHub Releases ---
if [ "${1:-}" = "upload" ]; then
    echo ""
    echo "=== Upload: Publishing GitHub Release ==="

    if ! command -v gh &> /dev/null; then
        echo "ERROR: gh CLI not found. Install with: brew install gh"
        exit 1
    fi

    # Build "What's Changed" from commits since last tag.
    # Works for both PRs and direct commits to master — nothing gets lost.
    PREV_TAG=$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || echo "")
    NOTES_BODY=""
    if [ -n "$PREV_TAG" ]; then
        COMMIT_LOG=$(git log --pretty=format:"* %s" "$PREV_TAG..HEAD" --no-merges 2>/dev/null || echo "")
        if [ -n "$COMMIT_LOG" ]; then
            NOTES_BODY="## What's Changed

$COMMIT_LOG

**Full Changelog**: https://github.com/$GITHUB_REPO/compare/$PREV_TAG...$TAG"
        fi
    fi

    if gh release view "$TAG" --repo "$GITHUB_REPO" &>/dev/null; then
        echo "Release $TAG already exists — replacing assets in place..."
        gh release upload "$TAG" \
            "$DMG_PATH" \
            "$APPCAST_PATH" \
            --clobber \
            --repo "$GITHUB_REPO"

        if [ -n "$NOTES_BODY" ]; then
            gh release edit "$TAG" \
                --title "Zion $VERSION" \
                --notes "$NOTES_BODY" \
                --repo "$GITHUB_REPO"
        else
            gh release edit "$TAG" \
                --title "Zion $VERSION" \
                --repo "$GITHUB_REPO"
        fi
    elif [ -n "$NOTES_BODY" ]; then
        gh release create "$TAG" \
            --title "Zion $VERSION" \
            --notes "$NOTES_BODY" \
            "$DMG_PATH" \
            "$APPCAST_PATH" \
            --repo "$GITHUB_REPO"
    else
        # First release or no previous tag — let GitHub generate notes
        gh release create "$TAG" \
            --title "Zion $VERSION" \
            --generate-notes \
            "$DMG_PATH" \
            "$APPCAST_PATH" \
            --repo "$GITHUB_REPO"
    fi

    echo ""
    echo "Release published: https://github.com/$GITHUB_REPO/releases/tag/$TAG"
    echo "Users running Zion will be notified automatically via Sparkle."
else
    echo ""
    echo "To upload to GitHub Releases, run:"
    echo "  ./scripts/release.sh upload"
fi
