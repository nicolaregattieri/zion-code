#!/usr/bin/env bash
set -euo pipefail

# Zion Release Script
# Builds app, creates DMG, signs it for Sparkle, generates appcast, and uploads.
#
# Usage:
#   ./scripts/release.sh          — build + sign + generate appcast (local only)
#   ./scripts/release.sh upload   — also upload to GitHub Releases (requires gh CLI)
#
# Prerequisites:
#   - Sparkle tools at /tmp/bin/ (sign_update). Install once with:
#       cd /tmp
#       curl -LO https://github.com/sparkle-project/Sparkle/releases/download/2.8.1/Sparkle-2.8.1.tar.xz
#       tar xf Sparkle-2.8.1.tar.xz
#   - EdDSA key pair in macOS Keychain (created automatically by sign_update on first run)
#   - gh CLI authenticated as repo owner (for upload)

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

DIST_DIR="$ROOT_DIR/dist"
DMG_PATH="$DIST_DIR/Zion.dmg"
APPCAST_PATH="$DIST_DIR/appcast.xml"
SPARKLE_BIN="/tmp/bin"
GITHUB_REPO="nicolaregattieri/zion-code"
DOWNLOAD_BASE="https://github.com/$GITHUB_REPO/releases/download"

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

# --- Step 1: Build app ---
echo ""
echo "=== Step 1/5: Building Zion.app ==="
./scripts/make-app.sh

# --- Read version from Info.plist ---
VERSION=$(defaults read "$DIST_DIR/Zion.app/Contents/Info" CFBundleShortVersionString)
BUILD=$(defaults read "$DIST_DIR/Zion.app/Contents/Info" CFBundleVersion)
TAG="v$VERSION"

echo "  Version: $VERSION (build $BUILD)"

# --- Step 2: Create DMG ---
echo ""
echo "=== Step 2/5: Creating DMG ==="
./scripts/make-dmg.sh

# --- Step 3: Sign DMG with EdDSA ---
echo ""
echo "=== Step 3/5: Signing DMG for Sparkle ==="
SIGN_OUTPUT=$("$SPARKLE_BIN/sign_update" "$DMG_PATH")
echo "$SIGN_OUTPUT"

# Parse signature and length from sign_update output
ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
DMG_LENGTH=$(echo "$SIGN_OUTPUT" | grep -o 'length="[^"]*"' | cut -d'"' -f2)

if [ -z "$ED_SIGNATURE" ] || [ -z "$DMG_LENGTH" ]; then
    echo "ERROR: Failed to parse signature from sign_update output"
    exit 1
fi

# --- Step 4: Generate appcast.xml ---
echo ""
echo "=== Step 4/5: Generating appcast.xml ==="
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

# --- Step 5: Upload to GitHub Releases ---
if [ "${1:-}" = "upload" ]; then
    echo ""
    echo "=== Step 5/5: Uploading to GitHub Releases ==="

    if ! command -v gh &> /dev/null; then
        echo "ERROR: gh CLI not found. Install with: brew install gh"
        exit 1
    fi

    # Check if release already exists
    if gh release view "$TAG" --repo "$GITHUB_REPO" &>/dev/null; then
        echo "Release $TAG already exists — updating assets..."
        gh release upload "$TAG" \
            "$DMG_PATH" \
            "$APPCAST_PATH" \
            --clobber \
            --repo "$GITHUB_REPO"
    else
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
