#!/usr/bin/env bash
set -euo pipefail

# Generate a proper AppIcon.icns from the new logo PNG
# Requires macOS command line tools (sips, iconutil)

PNG_SOURCE="Resources/logo.png"
ICONSET="Resources/AppIcon.iconset"

if [ ! -f "$PNG_SOURCE" ]; then
    echo "Erro: logo_new.png não encontrado. Execute generate_icon.swift primeiro."
    exit 1
fi

mkdir -p "$ICONSET"

# Generate all required sizes for macOS
sips -z 16 16     "$PNG_SOURCE" --out "$ICONSET/icon_16x16.png"
sips -z 32 32     "$PNG_SOURCE" --out "$ICONSET/icon_16x16@2x.png"
sips -z 32 32     "$PNG_SOURCE" --out "$ICONSET/icon_32x32.png"
sips -z 64 64     "$PNG_SOURCE" --out "$ICONSET/icon_32x32@2x.png"
sips -z 128 128   "$PNG_SOURCE" --out "$ICONSET/icon_128x128.png"
sips -z 256 256   "$PNG_SOURCE" --out "$ICONSET/icon_128x128@2x.png"
sips -z 256 256   "$PNG_SOURCE" --out "$ICONSET/icon_256x256.png"
sips -z 512 512   "$PNG_SOURCE" --out "$ICONSET/icon_256x256@2x.png"
sips -z 512 512   "$PNG_SOURCE" --out "$ICONSET/icon_512x512.png"
sips -z 1024 1024 "$PNG_SOURCE" --out "$ICONSET/icon_512x512@2x.png"

# Convert iconset to icns
iconutil -c icns "$ICONSET" -o Resources/ZionAppIcon.icns

# Update xcassets if it exists
XC_ASSETS="Resources/Assets.xcassets/AppIcon.appiconset"
if [ -d "$XC_ASSETS" ]; then
    cp "$ICONSET/icon_16x16.png"       "$XC_ASSETS/icon_16.png"
    cp "$ICONSET/icon_16x16@2x.png"    "$XC_ASSETS/icon_16@2x.png"
    cp "$ICONSET/icon_32x32.png"       "$XC_ASSETS/icon_32.png"
    cp "$ICONSET/icon_32x32@2x.png"    "$XC_ASSETS/icon_32@2x.png"
    cp "$ICONSET/icon_128x128.png"     "$XC_ASSETS/icon_128.png"
    cp "$ICONSET/icon_128x128@2x.png"  "$XC_ASSETS/icon_128@2x.png"
    cp "$ICONSET/icon_256x256.png"     "$XC_ASSETS/icon_256.png"
    cp "$ICONSET/icon_256x256@2x.png"  "$XC_ASSETS/icon_256@2x.png"
    cp "$ICONSET/icon_512x512.png"     "$XC_ASSETS/icon_512.png"
    cp "$ICONSET/icon_512x512@2x.png"  "$XC_ASSETS/icon_512@2x.png"
fi

# Cleanup
rm -rf "$ICONSET"
rm "$PNG_SOURCE"

echo "AppIcon.icns atualizado com sucesso!"
