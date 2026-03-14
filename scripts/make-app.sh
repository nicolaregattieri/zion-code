#!/usr/bin/env bash
set -euo pipefail

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

swift build -c release

APP_DIR="$ROOT_DIR/dist/Zion.app"
BIN_PATH="$ROOT_DIR/.build/release/Zion"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$APP_DIR/Contents/Frameworks"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/Zion"

# Add rpath so @rpath/Sparkle.framework resolves to Contents/Frameworks/
install_name_tool -add_rpath @executable_path/../Frameworks "$APP_DIR/Contents/MacOS/Zion"

# Copy resources bundle
BUNDLE_PATH="$(find .build -name "Zion_Zion.bundle" | grep "/release/" | head -n 1)"
if [ -n "$BUNDLE_PATH" ]; then
  cp -R "$BUNDLE_PATH" "$APP_DIR/Contents/Resources/"
fi

if [ -f "$ROOT_DIR/Resources/ZionAppIcon.icns" ]; then
  cp "$ROOT_DIR/Resources/ZionAppIcon.icns" "$APP_DIR/Contents/Resources/ZionAppIcon.icns"
fi

# Copy fonts from Resources folder
cp "$ROOT_DIR"/Resources/*.ttf "$APP_DIR/Contents/Resources/" 2>/dev/null || true
cp "$ROOT_DIR"/Resources/*.otf "$APP_DIR/Contents/Resources/" 2>/dev/null || true

# Copy Sparkle framework for auto-updates
SPARKLE_FW="$(find .build/artifacts -name "Sparkle.framework" -path "*/macos-*" 2>/dev/null | head -n 1)"
if [ -n "$SPARKLE_FW" ]; then
  cp -R "$SPARKLE_FW" "$APP_DIR/Contents/Frameworks/"
fi

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>Zion</string>
  <key>CFBundleDisplayName</key>
  <string>Zion</string>
  <key>CFBundleIdentifier</key>
  <string>com.nicolaregattieri.zion.app</string>
  <key>CFBundleVersion</key>
  <string>28</string>
  <key>CFBundleShortVersionString</key>
  <string>1.6.7</string>
  <key>CFBundleExecutable</key>
  <string>Zion</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>ZionAppIcon.icns</string>
  <key>CFBundleIconName</key>
  <string>ZionAppIcon</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSDocumentsFolderUsageDescription</key>
  <string>Zion needs access to your Documents folder to open and manage Git repositories.</string>
  <key>NSDownloadsFolderUsageDescription</key>
  <string>Zion needs access to your Downloads folder to open and manage Git repositories.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Zion needs microphone access for voice-to-text input in the terminal.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>Zion uses speech recognition to transcribe voice input for the terminal.</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>SUFeedURL</key>
  <string>https://github.com/nicolaregattieri/zion-code/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key>
  <string>4UJJHDAuD5klxnaOjA8q/4pd/tVSygoSNWZ2W/IQ6hQ=</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUScheduledCheckInterval</key>
  <integer>86400</integer>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>
      <string>Source Code</string>
      <key>CFBundleTypeRole</key>
      <string>Editor</string>
      <key>LSHandlerRank</key>
      <string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.source-code</string>
        <string>public.shell-script</string>
        <string>public.script</string>
        <string>public.text</string>
        <string>public.plain-text</string>
        <string>public.json</string>
        <string>public.xml</string>
        <string>public.yaml</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

chmod +x "$APP_DIR/Contents/MacOS/Zion"

# Strip extended attributes that break codesign (resource forks from cp)
xattr -cr "$APP_DIR"

# Re-sign app bundle (install_name_tool invalidates the ad-hoc signature from swift build)
# Set CODESIGN_IDENTITY in your environment for notarization (e.g., "Developer ID Application: Your Name (TEAMID)")
# When unset or "-", falls back to ad-hoc signing without entitlements.
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

if [ "$CODESIGN_IDENTITY" != "-" ]; then
  sign_with_identity() {
    local target="$1"
    shift
    codesign --force --sign "$CODESIGN_IDENTITY" --timestamp "$@" "$target"
  }

  # Sign nested Sparkle code explicitly before sealing the app bundle.
  SPARKLE_ROOT="$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B"
  if [ -d "$SPARKLE_ROOT" ]; then
    if [ -f "$SPARKLE_ROOT/Autoupdate" ]; then
      sign_with_identity "$SPARKLE_ROOT/Autoupdate" --options runtime
    fi

    if [ -d "$SPARKLE_ROOT/XPCServices/Downloader.xpc" ]; then
      sign_with_identity "$SPARKLE_ROOT/XPCServices/Downloader.xpc" --options runtime
    fi

    if [ -d "$SPARKLE_ROOT/XPCServices/Installer.xpc" ]; then
      sign_with_identity "$SPARKLE_ROOT/XPCServices/Installer.xpc" --options runtime
    fi

    if [ -d "$SPARKLE_ROOT/Updater.app" ]; then
      sign_with_identity "$SPARKLE_ROOT/Updater.app" --options runtime
    fi

    sign_with_identity "$APP_DIR/Contents/Frameworks/Sparkle.framework"
  fi

  sign_with_identity "$APP_DIR/Contents/MacOS/Zion" \
    --options runtime \
    --entitlements "$ROOT_DIR/Zion.entitlements"

  sign_with_identity "$APP_DIR" \
    --options runtime \
    --entitlements "$ROOT_DIR/Zion.entitlements"
  echo "Signed with identity: $CODESIGN_IDENTITY (hardened runtime + entitlements)"
else
  # Ad-hoc signing for local development
  codesign --force --deep --sign - "$APP_DIR"
  echo "Signed ad-hoc (set CODESIGN_IDENTITY for notarization)"
fi

# Nudge Finder/LaunchServices caches by bumping bundle mtimes after final signing
touch "$APP_DIR/Contents/Info.plist" "$APP_DIR"

echo "App gerado em: $APP_DIR"
