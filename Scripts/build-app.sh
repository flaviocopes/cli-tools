#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
APP="$ROOT/dist/CLI Tools.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"

cd "$ROOT"
swift build -c release --product CliToolsApp

rm -rf "$APP"
mkdir -p "$MACOS"
cp ".build/release/CliToolsApp" "$MACOS/CLI Tools"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>CLI Tools</string>
  <key>CFBundleExecutable</key>
  <string>CLI Tools</string>
  <key>CFBundleIdentifier</key>
  <string>com.flaviocopes.clitools</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>CLI Tools</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "$APP"
