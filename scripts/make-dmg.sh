#!/usr/bin/env bash
set -euo pipefail

# Zion DMG Generator — Premium Branded Installer

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="Zion"
APP_PATH="$DIST_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
DMG_TEMP="$DIST_DIR/${APP_NAME}_temp.dmg"
VOLUME_NAME="$APP_NAME"
BG_IMAGE="$ROOT_DIR/Resources/dmg-background@2x.png"

WIN_WIDTH=660
WIN_HEIGHT=500
ICON_SIZE=128
APPS_ICON_X=175
APPS_ICON_Y=190
APP_ICON_X=485
APP_ICON_Y=190

echo "Creating premium DMG for $APP_NAME..."

# Eject any existing Zion volume (e.g. from a previous DMG)
hdiutil detach "/Volumes/$VOLUME_NAME" 2>/dev/null || true

if [ ! -d "$APP_PATH" ]; then
    echo "Error: $APP_PATH not found. Run ./scripts/make-app.sh first."
    exit 1
fi

rm -f "$DMG_PATH" "$DMG_TEMP"

# Create read-write DMG
APP_SIZE_KB=$(du -sk "$APP_PATH" | cut -f1)
DMG_SIZE_KB=$((APP_SIZE_KB + 20480))
hdiutil create -size "${DMG_SIZE_KB}k" -volname "$VOLUME_NAME" -fs HFS+ "$DMG_TEMP"

# Mount
MOUNT_OUTPUT=$(hdiutil attach "$DMG_TEMP" -readwrite -noverify -noautoopen)
DEVICE=$(echo "$MOUNT_OUTPUT" | grep '/dev/' | head -1 | awk '{print $1}')
MOUNT_POINT="/Volumes/$VOLUME_NAME"
sleep 1

# Copy contents
cp -R "$APP_PATH" "$MOUNT_POINT/"
ln -s /Applications "$MOUNT_POINT/Applications"

mkdir "$MOUNT_POINT/.background"
cp "$BG_IMAGE" "$MOUNT_POINT/.background/background@2x.png"

# Volume icon
ICON_PATH="$APP_PATH/Contents/Resources/ZionAppIcon.icns"
if [ -f "$ICON_PATH" ]; then
    cp "$ICON_PATH" "$MOUNT_POINT/.VolumeIcon.icns"
    SetFile -c icnC "$MOUNT_POINT/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "$MOUNT_POINT" 2>/dev/null || true
fi

# Hide system files
chflags hidden "$MOUNT_POINT/.background" 2>/dev/null || true
chflags hidden "$MOUNT_POINT/.VolumeIcon.icns" 2>/dev/null || true
chflags hidden "$MOUNT_POINT/.fseventsd" 2>/dev/null || true

# Style with AppleScript
echo "Applying styling..."
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        delay 2

        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, $((200 + WIN_WIDTH)), $((120 + WIN_HEIGHT))}

        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to $ICON_SIZE
        set text size of viewOptions to 12
        set label position of viewOptions to bottom
        set background picture of viewOptions to file ".background:background@2x.png"

        set position of item "$APP_NAME.app" of container window to {$APP_ICON_X, $APP_ICON_Y}
        set position of item "Applications" of container window to {$APPS_ICON_X, $APPS_ICON_Y}

        try
            set position of item ".background" of container window to {900, 900}
        end try
        try
            set position of item ".fseventsd" of container window to {900, 900}
        end try
        try
            set position of item ".VolumeIcon.icns" of container window to {900, 900}
        end try

        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

sync
sleep 2
hdiutil detach "$DEVICE" -quiet

# Compress
echo "Compressing..."
hdiutil convert "$DMG_TEMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"
rm -f "$DMG_TEMP"

echo "DMG created: $DMG_PATH ($(du -sh "$DMG_PATH" | cut -f1))"
