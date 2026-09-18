#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

VERSION=1.9.5
SHA256=eac70be43c503997ff5176cfec5a2240d833f9748b5e7375f26ecfd222d03eeb
URL="https://fliqlo.com/download/Fliqlo%20$VERSION.dmg"
REFERER="https://fliqlo.com/"

SAVER_DIR="$HOME/Library/Screen Savers"
SAVER="$SAVER_DIR/Fliqlo.saver"

installed_version() {
  [[ -d "$SAVER" ]] || return 1
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$SAVER/Contents/Info.plist" 2>/dev/null
}

have="$(installed_version || true)"

if [[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]]; then
  if [[ "$have" == "$VERSION" ]]; then
    echo "  fliqlo: $VERSION already installed, would skip"
  else
    echo "  fliqlo: would install $VERSION over ${have:-nothing}"
  fi
  exit 0
fi

if [[ "$have" == "$VERSION" ]]; then
  echo "Fliqlo $VERSION already installed, skipping"
  exit 0
fi

tmp="$(mktemp -d)"
mnt="$tmp/mnt"
cleanup() {
  [[ -d "$mnt" ]] && hdiutil detach "$mnt" -quiet -force 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

echo "Fliqlo: downloading v$VERSION..."
curl -fsSL -e "$REFERER" "$URL" -o "$tmp/fliqlo.dmg"

echo "$SHA256  $tmp/fliqlo.dmg" | shasum -a 256 -c - >/dev/null

mkdir -p "$mnt"
hdiutil attach -nobrowse -readonly -mountpoint "$mnt" "$tmp/fliqlo.dmg" >/dev/null

mkdir -p "$SAVER_DIR"
rm -rf "$SAVER"
ditto "$mnt/Fliqlo.saver" "$SAVER"

echo "Fliqlo $VERSION installed to $SAVER"
