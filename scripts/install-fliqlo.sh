#!/usr/bin/env bash
#
# Install the Fliqlo screen saver from the upstream dmg instead of the Homebrew
# cask.
#
# Not a packaging preference: macos-bootstrap.sh selects the screen saver by
# writing WallpaperAgent's store, and that needs the .saver bundle on disk at
# selection time. The cask lives in brew/Brewfile.apps, which runs after the
# bootstrap, so on a fresh machine the selection always warned and skipped and
# the choice only took on a second run.
#
# fliqlo.com refuses hotlinked downloads: without a Referer the dmg URL 301s to
# the homepage and curl happily writes 17KB of HTML. Pinned and verified against
# Homebrew's recorded sha256, same tradeoff as install-alacritty.sh - content
# integrity, checked before anything mounts it.

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

# Verify before mounting: hdiutil parses attacker-controlled filesystem
# metadata, so an unverified image should never be attached. This also catches
# the hotlink-block HTML, which is a valid file and a useless one.
echo "$SHA256  $tmp/fliqlo.dmg" | shasum -a 256 -c - >/dev/null

mkdir -p "$mnt"
hdiutil attach -nobrowse -readonly -mountpoint "$mnt" "$tmp/fliqlo.dmg" >/dev/null

# ditto, not cp -R: it preserves the bundle's extended attributes. Remove the
# old bundle first so files dropped between releases can't survive as orphans.
mkdir -p "$SAVER_DIR"
rm -rf "$SAVER"
ditto "$mnt/Fliqlo.saver" "$SAVER"

echo "Fliqlo $VERSION installed to $SAVER"
