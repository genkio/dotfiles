#!/usr/bin/env bash
#
# Install Alacritty from the upstream dmg, replacing the Homebrew cask.
#
# Homebrew disabled the cask on 2026-09-01 (disable_reason: fails_gatekeeper_check).
# The upstream dmg is ad-hoc signed - `TeamIdentifier=not set`, CodeDirectory
# `flags=0x2(adhoc)` - so it is neither Developer ID signed nor notarized and
# `spctl -a` rejects it. Upstream's latest release is still v0.17.0 (2026-04-06),
# so there is nothing to bump to; the cask stays disabled until they ship a
# notarized build.
#
# The tradeoff this script makes: no signature to check, so it pins an exact
# version and verifies the dmg against Homebrew's recorded sha256 for that
# release, then clears the quarantine flag. Content integrity instead of
# publisher identity. Drop this script and restore `cask "alacritty"` in
# brew/Brewfile.dev once the cask is re-enabled.

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

if [[ "$(installed_version || true)" == "$VERSION" ]]; then
  echo "Alacritty $VERSION already installed, skipping"
  exit 0
fi

tmp="$(mktemp -d)"
mnt="$tmp/mnt"
cleanup() {
  # -quiet: a detach of a volume that never mounted is expected on the early
  # failure paths and its error is noise.
  [[ -d "$mnt" ]] && hdiutil detach "$mnt" -quiet -force 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

echo "Alacritty: downloading v$VERSION (cask is disabled upstream)..."
curl -fsSL "$URL" -o "$tmp/alacritty.dmg"

# Verify before mounting: hdiutil parses attacker-controlled filesystem
# metadata, so an unverified image should never be attached.
echo "$SHA256  $tmp/alacritty.dmg" | shasum -a 256 -c - >/dev/null

# -mountpoint avoids parsing hdiutil's output for the /Volumes path.
mkdir -p "$mnt"
hdiutil attach -nobrowse -readonly -mountpoint "$mnt" "$tmp/alacritty.dmg" >/dev/null

# ditto, not cp -R: it preserves the bundle's extended attributes. Remove any
# existing bundle first so files dropped between releases can't survive as
# orphans inside the new one.
rm -rf "$APP"
ditto "$mnt/Alacritty.app" "$APP"

# The dmg came from a browser-style download, so LaunchServices would show the
# unidentified-developer dialog on first launch and offer no override for an
# ad-hoc signature.
xattr -dr com.apple.quarantine "$APP"

# Replaces the cask's `binary` artifacts. ~/.local/bin rather than brew's prefix:
# a non-brew symlink in there trips `brew doctor`, and setup-dev.sh already puts
# ~/.local/bin on PATH.
mkdir -p "$BIN_DIR"
ln -sfn "$APP/Contents/MacOS/alacritty" "$BIN_DIR/alacritty"

# TERM=alacritty has to resolve outside the app too (tmux, ssh into this box).
mkdir -p "$TERMINFO_DIR"
ln -sfn "$APP/Contents/Resources/61/alacritty" "$TERMINFO_DIR/alacritty"
ln -sfn "$APP/Contents/Resources/61/alacritty-direct" "$TERMINFO_DIR/alacritty-direct"

echo "Alacritty $VERSION installed to $APP"
