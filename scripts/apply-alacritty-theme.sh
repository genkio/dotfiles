#!/usr/bin/env bash
#
# Write the active Alacritty colors file from the current effective theme
# (Flexoki Light light / TokyoNight Storm dark). Alacritty can't detect macOS
# light/dark itself, so this is run by scripts/theme-toggle.sh (manual toggle)
# and by Hammerspoon's theme_watcher.lua (on AppleInterfaceThemeChangedNotification
# and at startup) to give Alacritty the same auto-switch behavior as Ghostty.
#
# alacritty.toml imports the destination file; live_config_reload picks up the
# rewrite. Atomic mv so a running Alacritty never reads a half-written file.

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
