#!/usr/bin/env bash
#
# Write the active Alacritty colors file for the current theme (Flexoki Light /
# TokyoNight Storm, per current-theme.sh). Run by theme-toggle.sh on a flip and
# seeded once by setup-dev.sh. alacritty.toml imports it; live_config_reload
# picks up the rewrite. Atomic mv so Alacritty never reads a half-written file.

set -euo pipefail

dotfiles="${DOTFILES_DIR:-$HOME/dotfiles}"
themes="$dotfiles/alacritty/.config/alacritty/themes"
active_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
active="$active_dir/alacritty-theme-active.toml"

theme="$("$dotfiles/scripts/current-theme.sh")"

if [ "$theme" = "dark" ]; then
  src="$themes/tokyonight-storm.toml"
else
  src="$themes/flexoki-light.toml"
fi

# Missing source (partial checkout / wrong DOTFILES_DIR): degrade gracefully so
# callers under `set -e` aren't aborted by a cosmetic seed step.
[ -f "$src" ] || exit 0

mkdir -p "$active_dir"
tmp="$active.tmp.$$"
cp "$src" "$tmp"
mv -f "$tmp" "$active"
