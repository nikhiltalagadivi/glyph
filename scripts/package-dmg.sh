#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
VENDOR_DIR="$ROOT_DIR/vendor"
OLLAMA_BIN="$VENDOR_DIR/ollama/ollama"
MODEL_DIR="$VENDOR_DIR/ollama-models"
PACKAGE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/tabnote-package.XXXXXX")"
APP_DIR="$PACKAGE_ROOT/Glyph.app"
DMG_ROOT="$PACKAGE_ROOT/dmgroot"
DMG_PATH="$ROOT_DIR/dist/Glyph.dmg"
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

rm -rf "$ROOT_DIR/dist/Glyph.app" "$DMG_PATH"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/Ollama"

cp "$BUILD_DIR/Glyph" "$APP_DIR/Contents/MacOS/Glyph"
cp "$OLLAMA_BIN" "$APP_DIR/Contents/Resources/Ollama/ollama"
ditto --noextattr --noqtn "$MODEL_DIR" "$APP_DIR/Contents/Resources/OllamaModels"

# Copy SwiftMath resource bundle (math fonts) to Contents/Resources
# (Swizzling logic in Extensions.swift redirects Bundle.module lookup here at runtime)
if [ -d "$BUILD_DIR/SwiftMath_SwiftMath.bundle" ]; then
  ditto --noextattr --noqtn "$BUILD_DIR/SwiftMath_SwiftMath.bundle" "$APP_DIR/Contents/Resources/SwiftMath_SwiftMath.bundle"
fi

# Copy App Icon
if [ -f "$ROOT_DIR/Resources/Glyph.icns" ]; then
  cp "$ROOT_DIR/Resources/Glyph.icns" "$APP_DIR/Contents/Resources/Glyph.icns"
fi

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Glyph</string>
  <key>CFBundleIdentifier</key>
  <string>com.tabnote.app</string>
  <key>CFBundleName</key>
  <string>Glyph</string>
  <key>CFBundleDisplayName</key>
  <string>Glyph</string>
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
  <key>CFBundleIconFile</key>
  <string>Glyph.icns</string>
</dict>
</plist>
PLIST

chmod -R u+w "$APP_DIR"
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"

mkdir -p "$DMG_ROOT"
ditto --noextattr --noqtn "$APP_DIR" "$DMG_ROOT/Glyph.app"
hdiutil create -volname "Glyph" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG_PATH"

# Also place the uncompressed .app in dist for easy access
cp -R "$APP_DIR" "$ROOT_DIR/dist/"

echo "Built DMG: $DMG_PATH"
echo "Built App: $ROOT_DIR/dist/Glyph.app"
