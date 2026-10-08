#!/bin/sh
# Builds a universal (Apple silicon and Intel) dist/CLI Tools Cabinet.app.
# Signs with Flavio's Developer ID when the certificate is in the keychain, and ad-hoc everywhere else (CI, forks).
# The version comes from Commands.version in Sources/CliToolsCLI/Commands.swift.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
APP="$ROOT/dist/CLI Tools Cabinet.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
ICON_SOURCE="$ROOT/Assets/AppIcon.png"
ICONSET="$ROOT/.build/AppIcon.iconset"

cd "$ROOT"
VERSION=$(sed -n 's/^ *static let version = "\(.*\)"$/\1/p' Sources/CliToolsCLI/Commands.swift)
swift build -c release --arch arm64 --arch x86_64 --product CliToolsApp

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"
cp ".build/apple/Products/Release/CliToolsApp" "$MACOS/CLI Tools Cabinet"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"
sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
cp "$ICON_SOURCE" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>CLI Tools Cabinet</string>
  <key>CFBundleExecutable</key>
  <string>CLI Tools Cabinet</string>
  <key>CFBundleIdentifier</key>
  <string>com.flaviocopes.clitools</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>CLI Tools Cabinet</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

IDENTITY=$(security find-identity -v -p codesigning | awk '/"Developer ID Application: Flavio Copes \(DGFKNTAG99\)"/ { print $2; exit }')
if [ -n "$IDENTITY" ]; then
  SIGNATURE="Developer ID"
  find "$APP" -type f | while read -r file; do
    case $(file -b "$file") in
      Mach-O*)
        codesign --force --options runtime --timestamp --sign "$IDENTITY" "$file"
        ;;
    esac
  done
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
  codesign --verify --strict "$APP"
else
  SIGNATURE="ad-hoc"
  codesign --force --deep --sign - "$APP"
  codesign --verify --deep --strict "$APP"
fi

echo "Built $APP $VERSION for $(lipo -archs "$MACOS/CLI Tools Cabinet"), $SIGNATURE signed"
echo "$APP"
