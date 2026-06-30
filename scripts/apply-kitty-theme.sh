#!/usr/bin/env bash
#
# Write the active kitty colors file for the current theme (Flexoki Light /
# TokyoNight Storm, per current-theme.sh), then reload any running kitty so the
# change applies live. Run by theme-toggle.sh on a flip and seeded once by
# setup-dev.sh. kitty.conf includes the active file LAST so it wins. Atomic mv so
# kitty never reads a half-written file.

set -euo pipefail

dotfiles="${DOTFILES_DIR:-$HOME/dotfiles}"
themes="$dotfiles/kitty/.config/kitty/themes"
active_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
active="$active_dir/kitty-theme-active.conf"

theme="$("$dotfiles/scripts/current-theme.sh")"

if [ "$theme" = "dark" ]; then
  src="$themes/tokyonight-storm.conf"
else
  src="$themes/flexoki-light.conf"
fi

# Missing source (partial checkout / wrong DOTFILES_DIR): degrade gracefully so
# callers under `set -e` aren't aborted by a cosmetic seed step.
[ -f "$src" ] || exit 0

mkdir -p "$active_dir"
tmp="$active.tmp.$$"
cp "$src" "$tmp"
mv -f "$tmp" "$active"

# Reload config in any running kitty so open windows pick up the new palette.
# SIGUSR1 is kitty's reload signal; no-op when no kitty is running.
pkill -USR1 -x kitty 2> /dev/null || true
