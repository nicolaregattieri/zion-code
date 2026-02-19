#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/clang-module-cache"

swift build -c release

APP_DIR="$ROOT_DIR/dist/Zion.app"
BIN_PATH="$ROOT_DIR/.build/release/Zion"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/Zion"

# Copy resources bundle
BUNDLE_PATH="$(find .build -name "Zion_Zion.bundle" | grep "/release/" | head -n 1)"
if [ -n "$BUNDLE_PATH" ]; then
  cp -R "$BUNDLE_PATH" "$APP_DIR/Contents/Resources/"
fi

if [ -f "$ROOT_DIR/Resources/ZionAppIcon.icns" ]; then
  cp "$ROOT_DIR/Resources/ZionAppIcon.icns" "$APP_DIR/Contents/Resources/ZionAppIcon.icns"
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
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleExecutable</key>
  <string>Zion</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>ZionAppIcon</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

chmod +x "$APP_DIR/Contents/MacOS/Zion"

echo "App gerado em: $APP_DIR"
