#!/usr/bin/env bash
#
# Install kitty's custom dock/app icon for the current macOS. Tahoe (26+) masks a
# full-bleed icon itself; older macOS expects a pre-shaped squircle - so the right
# variant differs per OS. Source icons are stow-tracked in the repo; this picks the
# matching one, drops it in the kitty config dir as kitty.app.{icns,png} (kitty
# loads that on launch), tells a running kitty to use it now, and bumps the Dock
# cache (macOS caches icons hard). Re-run by setup-dev.sh so new machines restore it.

set -euo pipefail

dotfiles="${DOTFILES_DIR:-$HOME/dotfiles}"
icons="$dotfiles/kitty/.config/kitty/icons"
dest="$HOME/.config/kitty"

# kitty not stowed yet (partial checkout): nothing to install into.
[ -d "$dest" ] || exit 0

major="$(sw_vers -productVersion 2> /dev/null | cut -d. -f1)"
[ -n "$major" ] || exit 0

rm -f "$dest/kitty.app.icns" "$dest/kitty.app.png"
if [ "$major" -ge 26 ]; then
  cp "$icons/kitty-tahoe.icns" "$dest/kitty.app.icns"
  applied="$dest/kitty.app.icns"
else
  cp "$icons/kitty-classic.png" "$dest/kitty.app.png"
  applied="$dest/kitty.app.png"
fi

# Apply to a running kitty so it shows without waiting for a relaunch.
if pgrep -x kitty > /dev/null 2>&1; then
  /Applications/kitty.app/Contents/MacOS/kitty +runpy \
    'from kitty.fast_data_types import cocoa_set_app_icon; import sys; cocoa_set_app_icon(*sys.argv[1:])' \
    "$applied" > /dev/null 2>&1 || true
fi

# Dock caches icons hard; force a refresh so the new one shows.
rm -f /var/folders/*/*/*/com.apple.dock.iconcache 2> /dev/null || true
killall Dock 2> /dev/null || true
