#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$PROJECT_DIR/build/macos/Build/Products/Release/odoo_auto_config.app"
DMG_PATH="$PROJECT_DIR/build/Workspace Configuration.dmg"

echo "=== Building Flutter macOS release ==="
cd "$PROJECT_DIR"
fvm flutter build macos --release

echo "=== Creating DMG ==="
TMP_DIR=$(mktemp -d)
cp -R "$APP_PATH" "$TMP_DIR/Workspace Configuration.app"
ln -s /Applications "$TMP_DIR/Applications"
rm -f "$DMG_PATH"
hdiutil create -volname "Workspace Configuration" -srcfolder "$TMP_DIR" -ov -format UDZO "$DMG_PATH"
rm -rf "$TMP_DIR"

echo ""
echo "=== Done ==="
echo "Output: $DMG_PATH"
ls -lh "$DMG_PATH"
