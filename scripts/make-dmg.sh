#!/usr/bin/env bash
set -euo pipefail

# Zion DMG Generator
# Uses native macOS tools (hdiutil)

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="Zion"
APP_PATH="$DIST_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
TEMP_DIR="$DIST_DIR/temp_dmg"

echo "🚀 Iniciando criação do DMG para $APP_NAME..."

# 1. Verificar se o app existe
if [ ! -d "$APP_PATH" ]; then
    echo "❌ Erro: $APP_PATH não encontrado. Rode ./scripts/make-app.sh primeiro."
    exit 1
fi

# 2. Limpar builds anteriores
rm -f "$DMG_PATH"
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

# 3. Preparar estrutura do DMG
echo "📦 Preparando arquivos..."
cp -R "$APP_PATH" "$TEMP_DIR/"
ln -s /Applications "$TEMP_DIR/Applications"

# 4. Criar a imagem de disco (DMG)
echo "💿 Criando imagem de disco..."
hdiutil create -volname "$APP_NAME" -srcfolder "$TEMP_DIR" -ov -format UDZO "$DMG_PATH"

# 5. Limpar temporários
rm -rf "$TEMP_DIR"

echo "✅ DMG gerado com sucesso em: $DMG_PATH"
echo "ℹ️  Dica: Para distribuição oficial, considere assinar o app com 'codesign' e o DMG com 'notarytool'."
