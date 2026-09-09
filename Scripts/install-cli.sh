#!/bin/sh

# Builds the clitools binary in release mode and symlinks it into a
# directory on your PATH. Defaults to ~/.local/bin. Pass another
# directory as the first argument to install somewhere else:
#
#   ./Scripts/install-cli.sh /opt/homebrew/bin

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BIN_DIR="${1:-$HOME/.local/bin}"
BINARY="$ROOT/.build/release/clitools"
LINK="$BIN_DIR/clitools"

cd "$ROOT"
swift build -c release --product clitools

mkdir -p "$BIN_DIR"
ln -sf "$BINARY" "$LINK"

echo "Installed $LINK -> $BINARY"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "Note: $BIN_DIR is not in your PATH. Add it to your shell config." ;;
esac
