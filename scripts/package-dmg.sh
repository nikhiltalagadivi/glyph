#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
VENDOR_DIR="$ROOT_DIR/vendor"
OLLAMA_BIN="$VENDOR_DIR/ollama/ollama"
MODEL_DIR="$VENDOR_DIR/ollama-models"
PACKAGE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/tabnote-package.XXXXXX")"
APP_DIR="$PACKAGE_ROOT/TabNote.app"
DMG_ROOT="$PACKAGE_ROOT/dmgroot"
DMG_PATH="$ROOT_DIR/dist/TabNote.dmg"
trap 'rm -rf "$PACKAGE_ROOT"' EXIT

swift build -c release --package-path "$ROOT_DIR"

if [ ! -x "$OLLAMA_BIN" ] || [ ! -d "$MODEL_DIR/manifests" ] || [ ! -d "$MODEL_DIR/blobs" ]; then
  cat <<MSG
Missing bundled AI runtime/model.

Run this first:
  scripts/vendor-ollama-runtime.sh
MSG
  exit 1
fi

rm -rf "$ROOT_DIR/dist/TabNote.app" "$DMG_PATH"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/Ollama"

cp "$BUILD_DIR/TabNote" "$APP_DIR/Contents/MacOS/TabNote"
cp "$OLLAMA_BIN" "$APP_DIR/Contents/Resources/Ollama/ollama"
ditto --noextattr --noqtn "$MODEL_DIR" "$APP_DIR/Contents/Resources/OllamaModels"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>TabNote</string>
  <key>CFBundleIdentifier</key>
  <string>com.tabnote.app</string>
  <key>CFBundleName</key>
  <string>TabNote</string>
  <key>CFBundleDisplayName</key>
  <string>TabNote</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
</dict>
</plist>
PLIST

xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"

mkdir -p "$DMG_ROOT"
ditto --noextattr --noqtn "$APP_DIR" "$DMG_ROOT/TabNote.app"
hdiutil create -volname "TabNote" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG_PATH"

echo "$DMG_PATH"
