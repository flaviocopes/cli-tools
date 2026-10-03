#!/bin/sh
# Builds the universal app, notarizes when signed with the Developer ID, staples the ticket,
# checks the signature survives zipping, and writes dist/CLI-Tools-<version>.zip for a GitHub release.
# Needs the Developer ID certificate in the keychain and a notarytool profile named "notary":
#   xcrun notarytool store-credentials notary --apple-id <apple id> --team-id DGFKNTAG99
# Usage: ./Scripts/build-release.sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"
VERSION=$(sed -n 's/^ *static let version = "\(.*\)"$/\1/p' Sources/CliToolsCLI/Commands.swift)
APP="$ROOT/dist/CLI Tools.app"
ZIP="$ROOT/dist/CLI-Tools-$VERSION.zip"
CHECK=$(mktemp -d)

rm -f "$ZIP"
./Scripts/build-app.sh >/dev/null

TEAM=$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')
if [ "$TEAM" = DGFKNTAG99 ]; then
  SIGNATURE="Developer ID"
else
  SIGNATURE="ad-hoc"
fi

lipo "$APP/Contents/MacOS/CLI Tools" -verify_arch arm64 x86_64
if [ "$SIGNATURE" = "Developer ID" ]; then
  codesign --verify --strict "$APP"
else
  codesign --verify --deep --strict "$APP"
fi

verify_zip() {
  zip_path=$1
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$zip_path"
  ditto -x -k "$zip_path" "$CHECK"
  if [ "$SIGNATURE" = "Developer ID" ]; then
    codesign --verify --strict "$CHECK/CLI Tools.app"
  else
    codesign --verify --deep --strict "$CHECK/CLI Tools.app"
  fi
  rm -rf "$CHECK"/*
}

if [ "$SIGNATURE" = "Developer ID" ]; then
  verify_zip "$ZIP"
  RESULT=$(xcrun notarytool submit "$ZIP" --keychain-profile notary --wait --output-format json)
  STATUS=$(printf '%s' "$RESULT" | plutil -extract status raw -o - -)
  if [ "$STATUS" != Accepted ]; then
    printf '%s\n' "$RESULT" >&2
    SUBMISSION_ID=$(printf '%s' "$RESULT" | plutil -extract id raw -o - -)
    xcrun notarytool log "$SUBMISSION_ID" --keychain-profile notary >&2
    rm -rf "$CHECK"
    exit 1
  fi

  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  verify_zip "$ZIP"
  spctl --assess --type execute --verbose "$APP"
  echo "Notarized $ZIP ($SIGNATURE signed)"
else
  ditto -c -k --keepParent "$APP" "$ZIP"
  ditto -x -k "$ZIP" "$CHECK"
  codesign --verify --deep --strict "$CHECK/CLI Tools.app"
  rm -rf "$CHECK"
  echo "$ZIP ($SIGNATURE signed)"
fi

rm -rf "$CHECK"
echo "$ZIP"
shasum -a 256 "$ZIP"
