#!/usr/bin/env bash
set -euo pipefail

# Zion Release Script
# Builds app, creates DMG, signs it for Sparkle, and generates appcast.
#
# Usage:
#   ./scripts/release.sh          — build + sign + generate appcast
#   ./scripts/release.sh upload   — also upload to GitHub Releases (requires gh CLI)

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

DIST_DIR="$ROOT_DIR/dist"
DMG_PATH="$DIST_DIR/Zion.dmg"
SPARKLE_BIN="/tmp/bin"

# --- Check Sparkle tools exist ---
if [ ! -f "$SPARKLE_BIN/sign_update" ] || [ ! -f "$SPARKLE_BIN/generate_appcast" ]; then
    echo "Sparkle tools not found at $SPARKLE_BIN"
    echo ""
    echo "Install them once with:"
    echo "  cd /tmp"
    echo "  curl -LO https://github.com/sparkle-project/Sparkle/releases/download/2.8.1/Sparkle-2.8.1.tar.xz"
    echo "  tar xf Sparkle-2.8.1.tar.xz"
    exit 1
fi

# --- Step 1: Build app ---
echo ""
echo "=== Step 1/4: Building Zion.app ==="
./scripts/make-app.sh

# --- Step 2: Create DMG ---
echo ""
echo "=== Step 2/4: Creating DMG ==="
./scripts/make-dmg.sh

# --- Step 3: Sign DMG with EdDSA ---
echo ""
echo "=== Step 3/4: Signing DMG for Sparkle ==="
SIGNATURE=$("$SPARKLE_BIN/sign_update" "$DMG_PATH")
echo "Signature info:"
echo "$SIGNATURE"

# --- Step 4: Generate appcast ---
echo ""
echo "=== Step 4/4: Generating appcast.xml ==="
"$SPARKLE_BIN/generate_appcast" "$DIST_DIR"
echo "Appcast generated at: $DIST_DIR/appcast.xml"

# --- Read version from Info.plist ---
VERSION=$(defaults read "$DIST_DIR/Zion.app/Contents/Info" CFBundleShortVersionString)

echo ""
echo "=== Release ready ==="
echo "  Version:  $VERSION"
echo "  DMG:      $DMG_PATH"
echo "  Appcast:  $DIST_DIR/appcast.xml"

# --- Optional: Upload to GitHub Releases ---
if [ "${1:-}" = "upload" ]; then
    echo ""
    echo "=== Uploading to GitHub Releases ==="

    if ! command -v gh &> /dev/null; then
        echo "gh CLI not found. Install with: brew install gh"
        exit 1
    fi

    TAG="v$VERSION"

    # Create tag and release, upload assets
    gh release create "$TAG" \
        --title "Zion $VERSION" \
        --generate-notes \
        "$DMG_PATH" \
        "$DIST_DIR/appcast.xml"

    echo ""
    echo "Release published: $TAG"
    echo "Users running Zion will be notified automatically."
else
    echo ""
    echo "To upload to GitHub Releases, run:"
    echo "  ./scripts/release.sh upload"
    echo ""
    echo "Or manually upload Zion.dmg + appcast.xml to a GitHub Release."
fi
