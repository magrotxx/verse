#!/bin/bash
# Verse installer
#
#   curl -fsSL https://raw.githubusercontent.com/cpt-nem0/verse/main/install.sh | bash
#
# Downloads the latest Verse.app release, installs it to /Applications, and
# clears the com.apple.quarantine flag that macOS Gatekeeper stamps on
# ad-hoc-signed apps downloaded from a browser (which is what causes the
# "Verse is damaged and can't be opened" message). Requires macOS 14+.

set -euo pipefail

APP_NAME="Verse.app"
ZIP_URL="https://github.com/cpt-nem0/verse/releases/latest/download/Verse.zip"
INSTALL_DIR="/Applications"

echo "Verse installer"
echo "  downloading latest release…"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

curl -fL --progress-bar -o "$TMP_DIR/Verse.zip" "$ZIP_URL"

echo "  extracting…"
ditto -x -k "$TMP_DIR/Verse.zip" "$TMP_DIR"

if [ ! -d "$TMP_DIR/$APP_NAME" ]; then
    echo "error: $APP_NAME not found in the downloaded archive" >&2
    exit 1
fi

echo "  installing to $INSTALL_DIR…"
if [ -d "$INSTALL_DIR/$APP_NAME" ]; then
    rm -rf "$INSTALL_DIR/$APP_NAME"
fi
mv "$TMP_DIR/$APP_NAME" "$INSTALL_DIR/$APP_NAME"

echo "  clearing quarantine flag (Verse is ad-hoc signed, not notarized)…"
xattr -cr "$INSTALL_DIR/$APP_NAME"

echo "  launching Verse…"
open "$INSTALL_DIR/$APP_NAME"

echo ""
echo "Done — Verse is installed at $INSTALL_DIR/$APP_NAME and running."
echo "Requires macOS 14 or later. Enjoy the music."
