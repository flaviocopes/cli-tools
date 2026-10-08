#!/bin/sh
# Builds a capture app from the real views and generated tools. Run it in the test VM.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"
BUILD="$ROOT/.build/screenshot"
APP="$BUILD/CLI Tools Cabinet Screenshot.app"
rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 6 -parse-as-library -target arm64-apple-macos14 -module-name CliToolsCore -emit-module -emit-module-path "$BUILD/CliToolsCore.swiftmodule" -emit-library -static -o "$BUILD/libCliToolsCore.a" Sources/CliToolsCore/*.swift
sed -n '/^struct CatalogView: View/,$p' Sources/CliToolsApp/CliToolsApp.swift > "$BUILD/CatalogView.swift"
{ printf 'import CliToolsCore\nimport SwiftUI\n'; cat "$BUILD/CatalogView.swift"; } > "$BUILD/CatalogViewWithImports.swift"
find Sources/CliToolsApp -name '*.swift' ! -name CliToolsApp.swift -exec swiftc -O -swift-version 6 -parse-as-library -target arm64-apple-macos14 -I "$BUILD" -L "$BUILD" -lCliToolsCore -o "$APP/Contents/MacOS/Screenshot" Scripts/screenshot.swift "$BUILD/CatalogViewWithImports.swift" {} +
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Screenshot</string><key>CFBundleIdentifier</key><string>com.flaviocopes.clitools.screenshot</string><key>CFBundleName</key><string>CLI Tools Cabinet Screenshot</string><key>CFBundlePackageType</key><string>APPL</string><key>NSHighResolutionCapable</key><true/></dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "$APP"
