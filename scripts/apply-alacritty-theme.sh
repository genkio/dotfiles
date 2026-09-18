#!/usr/bin/env bash

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

[ -f "$src" ] || exit 0

mkdir -p "$active_dir"
tmp="$active.tmp.$$"
cp "$src" "$tmp"
mv -f "$tmp" "$active"
