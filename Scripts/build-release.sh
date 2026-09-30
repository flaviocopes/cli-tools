#!/bin/sh
# Builds the universal app, checks the signature survives zipping, and writes
# dist/CLI-Tools-<version>.zip for a GitHub release.
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

lipo "$APP/Contents/MacOS/CLI Tools" -verify_arch arm64 x86_64
codesign --verify --deep --strict "$APP"
ditto -c -k --keepParent "$APP" "$ZIP"

ditto -x -k "$ZIP" "$CHECK"
codesign --verify --deep --strict "$CHECK/CLI Tools.app"
rm -rf "$CHECK"

echo "$ZIP"
shasum -a 256 "$ZIP"
