#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

VERSION=0.17.0
SHA256=ad8d7de35fb38e43184776cac6dfee05ca325caa0b6639a06a55e54e4b026620
URL="https://github.com/alacritty/alacritty/releases/download/v$VERSION/Alacritty-v$VERSION.dmg"

APP=/Applications/Alacritty.app
BIN_DIR="$HOME/.local/bin"
TERMINFO_DIR="$HOME/.terminfo/61"

installed_version() {
  [[ -d "$APP" ]] || return 1
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$APP/Contents/Info.plist" 2>/dev/null
}

have="$(installed_version || true)"

if [[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]]; then
  if [[ "$have" == "$VERSION" ]]; then
    echo "  alacritty: $VERSION already installed, would skip"
  else
    echo "  alacritty: would install $VERSION over ${have:-nothing}"
  fi
  exit 0
fi

if [[ "$have" == "$VERSION" ]]; then
  echo "Alacritty $VERSION already installed, skipping"
  exit 0
fi

tmp="$(mktemp -d)"
mnt="$tmp/mnt"
cleanup() {
  [[ -d "$mnt" ]] && hdiutil detach "$mnt" -quiet -force 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

echo "Alacritty: downloading v$VERSION (cask is disabled upstream)..."
curl -fsSL "$URL" -o "$tmp/alacritty.dmg"

echo "$SHA256  $tmp/alacritty.dmg" | shasum -a 256 -c - >/dev/null

mkdir -p "$mnt"
hdiutil attach -nobrowse -readonly -mountpoint "$mnt" "$tmp/alacritty.dmg" >/dev/null

rm -rf "$APP"
ditto "$mnt/Alacritty.app" "$APP"

xattr -dr com.apple.quarantine "$APP"

mkdir -p "$BIN_DIR"
ln -sfn "$APP/Contents/MacOS/alacritty" "$BIN_DIR/alacritty"

mkdir -p "$TERMINFO_DIR"
ln -sfn "$APP/Contents/Resources/61/alacritty" "$TERMINFO_DIR/alacritty"
ln -sfn "$APP/Contents/Resources/61/alacritty-direct" "$TERMINFO_DIR/alacritty-direct"

echo "Alacritty $VERSION installed to $APP"
