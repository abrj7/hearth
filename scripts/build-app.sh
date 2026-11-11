#!/bin/bash
# Builds dist/Hearth.app. Pass --install to also copy it into /Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN=.build/release/Hearth
APP=dist/Hearth.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Hearth"

# App icon, drawn by the app itself.
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
"$BIN" --icon "$ICONSET/base.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ICONSET/base.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$ICONSET/base.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
rm "$ICONSET/base.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Hearth</string>
  <key>CFBundleDisplayName</key><string>Hearth</string>
  <key>CFBundleIdentifier</key><string>com.abrj7.hearth</string>
  <key>CFBundleExecutable</key><string>Hearth</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Hearth reads the current track from Spotify and Apple Music, and plays, pauses or skips when you click the record player.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Hearth 2>/dev/null && sleep 1 || true
  rm -rf /Applications/Hearth.app
  cp -R "$APP" /Applications/Hearth.app
  open /Applications/Hearth.app
  echo "Installed to /Applications/Hearth.app"
fi
