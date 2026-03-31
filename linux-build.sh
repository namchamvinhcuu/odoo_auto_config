#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLE_DIR="$PROJECT_DIR/build/linux/x64/release/bundle"
APPDIR="$PROJECT_DIR/build/AppDir"
OUTPUT="$PROJECT_DIR/build/WorkspaceConfiguration.AppImage"
APPIMAGETOOL="/tmp/appimagetool-x86_64.AppImage"

echo "=== Building Flutter Linux release ==="
cd "$PROJECT_DIR"
fvm flutter build linux --release

echo "=== Creating AppDir ==="
rm -rf "$APPDIR"
mkdir -p "$APPDIR"

# Copy entire bundle (binary, lib/, data/ must stay together)
cp -r "$BUNDLE_DIR/"* "$APPDIR/"

# Icon
cp "$PROJECT_DIR/workspaces.png" "$APPDIR/workspace-configuration.png"

# Desktop entry
cat > "$APPDIR/workspace-configuration.desktop" <<EOF
[Desktop Entry]
Name=Workspace Configuration
Exec=WorkspaceConfiguration
Icon=workspace-configuration
Type=Application
Categories=Development;
Comment=Setup and manage development environments
EOF

# AppRun
cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/bash
SELF=$(readlink -f "$0")
HERE=${SELF%/*}
export LD_LIBRARY_PATH="${HERE}/lib:${LD_LIBRARY_PATH}"
exec "${HERE}/WorkspaceConfiguration" "$@"
EOF
chmod +x "$APPDIR/AppRun"

echo "=== Downloading appimagetool (if needed) ==="
if [ ! -f "$APPIMAGETOOL" ]; then
    curl -fsSL -o "$APPIMAGETOOL" "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
    chmod +x "$APPIMAGETOOL"
fi

echo "=== Building AppImage ==="
rm -f "$OUTPUT"
ARCH=x86_64 "$APPIMAGETOOL" --appimage-extract-and-run --no-appstream "$APPDIR" "$OUTPUT"

echo ""
echo "=== Done ==="
echo "Output: $OUTPUT"
ls -lh "$OUTPUT"
